#!/bin/bash
# =============================================================================
# CASO 6 — Deploy completo del pipeline AWS
# Idempotente: ejecutalo tantas veces como quieras, nunca duplica recursos.
# Uso: bash deploy_caso6_v2.sh
# =============================================================================

set -e

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
BLUE='\033[0;34m'; CYAN='\033[0;36m'; BOLD='\033[1m'; NC='\033[0m'

ok()   { echo -e "${GREEN}  ✓ $1${NC}"; }
info() { echo -e "${CYAN}  → $1${NC}"; }
warn() { echo -e "${YELLOW}  ⚠ $1${NC}"; }
err()  { echo -e "${RED}  ✗ ERROR: $1${NC}"; exit 1; }
step() {
  echo -e "\n${BOLD}${BLUE}══════════════════════════════════════════${NC}"
  echo -e "${BOLD}${BLUE}  PASO $1: $2${NC}"
  echo -e "${BOLD}${BLUE}══════════════════════════════════════════${NC}"
}

# ── CONFIGURACION ─────────────────────────────────────────────────────────────
AWS_ACCESS_KEY_ID="AKIAZUFJBE6SECQNOEMG"
AWS_SECRET_ACCESS_KEY="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"
AWS_REGION="us-east-1"

AVIATIONSTACK_API_KEY="43264c19ddec7d362c122861ec9c6fb2"
WEATHERAPI_KEY="95a06619dccc4aacba6224744260306"
DELAY_API_USER="shmuel-api-client"
DELAY_API_PASS="Tk6UVWfxTOSyvjsbuh0JRpveavkZEzQ3"

BUCKET_RAW="caso6-raw"
BUCKET_PROCESSED="caso6-processed"
BUCKET_ATHENA="caso6-athena-results"
BUCKET_CURATED="caso6-curated"
ROLE_LAMBDA="caso6-lambda-role"
ROLE_GLUE="caso6-glue-role"
ROLE_SFN="caso6-stepfunctions-role"
ROLE_EB="caso6-eventbridge-role"

echo -e "\n${BOLD}╔══════════════════════════════════════════╗${NC}"
echo -e "${BOLD}║     CASO 6 — Deploy AWS Pipeline v2      ║${NC}"
echo -e "${BOLD}╚══════════════════════════════════════════╝${NC}"

# ═════════════════════════════════════════════════════════════════════════════
# PASO 0 — INSTALAR Y CONFIGURAR AWS CLI
# ═════════════════════════════════════════════════════════════════════════════
step "0" "Instalar y configurar AWS CLI"

if [[ "$AWS_ACCESS_KEY_ID" == "AQUI_TU_ACCESS_KEY" ]]; then
  err "Edita el script: reemplaza AQUI_TU_ACCESS_KEY y AQUI_TU_SECRET_KEY con tus credenciales reales."
fi

if ! command -v aws &>/dev/null; then
  info "AWS CLI no encontrado. Instalando..."
  if [[ "$OSTYPE" == "darwin"* ]]; then
    curl -s "https://awscli.amazonaws.com/AWSCLIV2.pkg" -o /tmp/AWSCLIV2.pkg
    sudo installer -pkg /tmp/AWSCLIV2.pkg -target / >/dev/null
  elif [[ "$OSTYPE" == "linux-gnu"* ]]; then
    curl -s "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o /tmp/awscliv2.zip
    unzip -q /tmp/awscliv2.zip -d /tmp/
    sudo /tmp/aws/install >/dev/null
  else
    err "Windows detectado. Abre PowerShell como Admin y ejecuta:\nmsiexec.exe /i https://awscli.amazonaws.com/AWSCLIV2.msi /quiet\nLuego corre este script desde Git Bash o WSL."
  fi
  ok "AWS CLI instalado"
else
  ok "AWS CLI ya instalado: $(aws --version 2>&1 | head -1)"
fi

aws configure set aws_access_key_id     "$AWS_ACCESS_KEY_ID"
aws configure set aws_secret_access_key "$AWS_SECRET_ACCESS_KEY"
aws configure set default.region        "$AWS_REGION"
aws configure set default.output        json

ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text 2>/dev/null) \
  || err "No se pudo conectar a AWS. Verifica tus credenciales."
ok "Conectado. Account ID: $ACCOUNT_ID"

# ═════════════════════════════════════════════════════════════════════════════
# PASO 1 — VPC (IDEMPOTENTE: busca por nombre antes de crear)
# ═════════════════════════════════════════════════════════════════════════════
step "1" "VPC e infraestructura de red"

# ── VPC ───────────────────────────────────────────────────────────────────────
info "Buscando VPC caso6-vpc..."
VPC_ID=$(aws ec2 describe-vpcs \
  --filters "Name=tag:Name,Values=caso6-vpc" \
  --query 'Vpcs[0].VpcId' --output text 2>/dev/null)

if [[ "$VPC_ID" == "None" || -z "$VPC_ID" ]]; then
  info "No existe. Creando VPC..."
  VPC_ID=$(aws ec2 create-vpc --cidr-block 10.0.0.0/16 \
    --query 'Vpc.VpcId' --output text)
  aws ec2 create-tags --resources "$VPC_ID" --tags Key=Name,Value=caso6-vpc
  aws ec2 modify-vpc-attribute --vpc-id "$VPC_ID" --enable-dns-hostnames
  aws ec2 modify-vpc-attribute --vpc-id "$VPC_ID" --enable-dns-support
  ok "VPC creada: $VPC_ID"
else
  ok "VPC ya existe: $VPC_ID (reutilizando)"
fi

# ── SUBRED A ──────────────────────────────────────────────────────────────────
info "Buscando subred caso6-subnet-a..."
SUBNET_A_ID=$(aws ec2 describe-subnets \
  --filters "Name=tag:Name,Values=caso6-subnet-a" "Name=vpc-id,Values=$VPC_ID" \
  --query 'Subnets[0].SubnetId' --output text 2>/dev/null)

if [[ "$SUBNET_A_ID" == "None" || -z "$SUBNET_A_ID" ]]; then
  info "No existe. Creando subred A..."
  SUBNET_A_ID=$(aws ec2 create-subnet \
    --vpc-id "$VPC_ID" --cidr-block 10.0.1.0/24 \
    --availability-zone "${AWS_REGION}a" \
    --query 'Subnet.SubnetId' --output text)
  aws ec2 create-tags --resources "$SUBNET_A_ID" --tags Key=Name,Value=caso6-subnet-a
  aws ec2 modify-subnet-attribute --subnet-id "$SUBNET_A_ID" --map-public-ip-on-launch
  ok "Subred A creada: $SUBNET_A_ID"
else
  ok "Subred A ya existe: $SUBNET_A_ID (reutilizando)"
fi

# ── SUBRED B ──────────────────────────────────────────────────────────────────
info "Buscando subred caso6-subnet-b..."
SUBNET_B_ID=$(aws ec2 describe-subnets \
  --filters "Name=tag:Name,Values=caso6-subnet-b" "Name=vpc-id,Values=$VPC_ID" \
  --query 'Subnets[0].SubnetId' --output text 2>/dev/null)

if [[ "$SUBNET_B_ID" == "None" || -z "$SUBNET_B_ID" ]]; then
  info "No existe. Creando subred B..."
  SUBNET_B_ID=$(aws ec2 create-subnet \
    --vpc-id "$VPC_ID" --cidr-block 10.0.2.0/24 \
    --availability-zone "${AWS_REGION}b" \
    --query 'Subnet.SubnetId' --output text)
  aws ec2 create-tags --resources "$SUBNET_B_ID" --tags Key=Name,Value=caso6-subnet-b
  aws ec2 modify-subnet-attribute --subnet-id "$SUBNET_B_ID" --map-public-ip-on-launch
  ok "Subred B creada: $SUBNET_B_ID"
else
  ok "Subred B ya existe: $SUBNET_B_ID (reutilizando)"
fi

# ── INTERNET GATEWAY ──────────────────────────────────────────────────────────
info "Buscando Internet Gateway caso6-igw..."
IGW_ID=$(aws ec2 describe-internet-gateways \
  --filters "Name=tag:Name,Values=caso6-igw" \
  --query 'InternetGateways[0].InternetGatewayId' --output text 2>/dev/null)

if [[ "$IGW_ID" == "None" || -z "$IGW_ID" ]]; then
  info "No existe. Creando IGW..."
  IGW_ID=$(aws ec2 create-internet-gateway \
    --query 'InternetGateway.InternetGatewayId' --output text)
  aws ec2 create-tags --resources "$IGW_ID" --tags Key=Name,Value=caso6-igw
  ok "IGW creado: $IGW_ID"
else
  ok "IGW ya existe: $IGW_ID (reutilizando)"
fi

# Adjuntar IGW a la VPC solo si no está adjunto
ATTACHED=$(aws ec2 describe-internet-gateways --internet-gateway-ids "$IGW_ID" \
  --query 'InternetGateways[0].Attachments[0].VpcId' --output text 2>/dev/null)
if [[ "$ATTACHED" == "None" || -z "$ATTACHED" ]]; then
  aws ec2 attach-internet-gateway --internet-gateway-id "$IGW_ID" --vpc-id "$VPC_ID"
  ok "IGW adjunto a $VPC_ID"
else
  ok "IGW ya estaba adjunto a $ATTACHED"
fi

# ── ROUTE TABLE ───────────────────────────────────────────────────────────────
info "Configurando Route Table..."
RTB_ID=$(aws ec2 describe-route-tables \
  --filters "Name=vpc-id,Values=$VPC_ID" "Name=association.main,Values=true" \
  --query 'RouteTables[0].RouteTableId' --output text)
aws ec2 create-tags --resources "$RTB_ID" --tags Key=Name,Value=caso6-rtb 2>/dev/null || true

# Agregar ruta solo si no existe
ROUTE_EXISTS=$(aws ec2 describe-route-tables --route-table-ids "$RTB_ID" \
  --query 'RouteTables[0].Routes[?DestinationCidrBlock==`0.0.0.0/0`].GatewayId' \
  --output text 2>/dev/null)
if [[ -z "$ROUTE_EXISTS" || "$ROUTE_EXISTS" == "None" ]]; then
  aws ec2 create-route --route-table-id "$RTB_ID" \
    --destination-cidr-block 0.0.0.0/0 --gateway-id "$IGW_ID" >/dev/null
  ok "Ruta 0.0.0.0/0 -> $IGW_ID creada"
else
  ok "Ruta 0.0.0.0/0 ya existe (apunta a $ROUTE_EXISTS)"
fi

# Asociar subredes solo si no están asociadas
for SUBNET_ID in "$SUBNET_A_ID" "$SUBNET_B_ID"; do
  ASSOC=$(aws ec2 describe-route-tables --route-table-ids "$RTB_ID" \
    --query "RouteTables[0].Associations[?SubnetId=='$SUBNET_ID'].RouteTableAssociationId" \
    --output text 2>/dev/null)
  if [[ -z "$ASSOC" || "$ASSOC" == "None" ]]; then
    aws ec2 associate-route-table --route-table-id "$RTB_ID" --subnet-id "$SUBNET_ID" >/dev/null
    ok "Subred $SUBNET_ID asociada a route table"
  else
    ok "Subred $SUBNET_ID ya estaba asociada"
  fi
done

# ═════════════════════════════════════════════════════════════════════════════
# PASO 2 — BUCKETS S3
# ═════════════════════════════════════════════════════════════════════════════
step "2" "Buckets S3"

for BUCKET in "$BUCKET_RAW" "$BUCKET_PROCESSED" "$BUCKET_ATHENA" "$BUCKET_CURATED"; do
  if aws s3api head-bucket --bucket "$BUCKET" 2>/dev/null; then
    ok "Bucket s3://$BUCKET ya existe (reutilizando)"
  else
    info "Creando bucket $BUCKET..."
    # us-east-1 no acepta LocationConstraint (es el default)
    if [[ "$AWS_REGION" == "us-east-1" ]]; then
      aws s3api create-bucket --bucket "$BUCKET" --region "$AWS_REGION" >/dev/null
    else
      aws s3api create-bucket --bucket "$BUCKET" --region "$AWS_REGION" \
        --create-bucket-configuration LocationConstraint="$AWS_REGION" >/dev/null
    fi
    aws s3api put-public-access-block --bucket "$BUCKET" \
      --public-access-block-configuration \
      "BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true"
    ok "Bucket creado: s3://$BUCKET"
  fi
done

# Carpetas (put-object es idempotente por naturaleza)
for FOLDER in flights weather delays; do
  aws s3api put-object --bucket "$BUCKET_RAW"       --key "$FOLDER/" >/dev/null
  aws s3api put-object --bucket "$BUCKET_PROCESSED" --key "$FOLDER/" >/dev/null
done
aws s3api put-object --bucket "$BUCKET_PROCESSED" --key "dbt-project/" >/dev/null
ok "Carpetas listas en raw y processed"

# ═════════════════════════════════════════════════════════════════════════════
# PASO 3 — ROLES IAM
# ═════════════════════════════════════════════════════════════════════════════
step "3" "Roles IAM"

ensure_role() {
  local ROLE_NAME=$1 TRUST=$2
  shift 2
  if aws iam get-role --role-name "$ROLE_NAME" &>/dev/null; then
    ok "Rol $ROLE_NAME ya existe (reutilizando)"
  else
    info "Creando rol $ROLE_NAME..."
    aws iam create-role --role-name "$ROLE_NAME" \
      --assume-role-policy-document "$TRUST" >/dev/null
    for POLICY_ARN in "$@"; do
      aws iam attach-role-policy --role-name "$ROLE_NAME" --policy-arn "$POLICY_ARN"
    done
    sleep 8  # IAM necesita unos segundos para propagar
    ok "Rol creado: $ROLE_NAME"
  fi
}

LAMBDA_TRUST='{"Version":"2012-10-17","Statement":[{"Effect":"Allow","Principal":{"Service":"lambda.amazonaws.com"},"Action":"sts:AssumeRole"}]}'
GLUE_TRUST='{"Version":"2012-10-17","Statement":[{"Effect":"Allow","Principal":{"Service":"glue.amazonaws.com"},"Action":"sts:AssumeRole"}]}'
SFN_TRUST='{"Version":"2012-10-17","Statement":[{"Effect":"Allow","Principal":{"Service":"states.amazonaws.com"},"Action":"sts:AssumeRole"}]}'
EB_TRUST='{"Version":"2012-10-17","Statement":[{"Effect":"Allow","Principal":{"Service":"scheduler.amazonaws.com"},"Action":"sts:AssumeRole"}]}'

ensure_role "$ROLE_LAMBDA" "$LAMBDA_TRUST" \
  "arn:aws:iam::aws:policy/AmazonS3FullAccess" \
  "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole" \
  "arn:aws:iam::aws:policy/AmazonVPCFullAccess"

ensure_role "$ROLE_GLUE" "$GLUE_TRUST" \
  "arn:aws:iam::aws:policy/AmazonS3FullAccess" \
  "arn:aws:iam::aws:policy/service-role/AWSGlueServiceRole" \
  "arn:aws:iam::aws:policy/AmazonAthenaFullAccess" \
  "arn:aws:iam::aws:policy/CloudWatchLogsFullAccess"

ensure_role "$ROLE_SFN" "$SFN_TRUST" \
  "arn:aws:iam::aws:policy/AWSLambdaRole" \
  "arn:aws:iam::aws:policy/AWSGlueConsoleFullAccess" \
  "arn:aws:iam::aws:policy/AmazonAthenaFullAccess" \
  "arn:aws:iam::aws:policy/CloudWatchLogsFullAccess"

# Rol EventBridge con policy inline para StartExecution
SFN_ARN_TEMP="arn:aws:states:${AWS_REGION}:${ACCOUNT_ID}:stateMachine:caso6-pipeline"
EB_POLICY="{\"Version\":\"2012-10-17\",\"Statement\":[{\"Effect\":\"Allow\",\"Action\":\"states:StartExecution\",\"Resource\":\"$SFN_ARN_TEMP\"}]}"
if aws iam get-role --role-name "$ROLE_EB" &>/dev/null; then
  ok "Rol $ROLE_EB ya existe (reutilizando)"
else
  info "Creando rol EventBridge..."
  aws iam create-role --role-name "$ROLE_EB" \
    --assume-role-policy-document "$EB_TRUST" >/dev/null
  aws iam put-role-policy --role-name "$ROLE_EB" \
    --policy-name "StartStepFunctions" --policy-document "$EB_POLICY"
  sleep 8
  ok "Rol EventBridge creado"
fi

LAMBDA_ROLE_ARN="arn:aws:iam::${ACCOUNT_ID}:role/${ROLE_LAMBDA}"
GLUE_ROLE_ARN="arn:aws:iam::${ACCOUNT_ID}:role/${ROLE_GLUE}"
SFN_ROLE_ARN="arn:aws:iam::${ACCOUNT_ID}:role/${ROLE_SFN}"
EB_ROLE_ARN="arn:aws:iam::${ACCOUNT_ID}:role/${ROLE_EB}"

# ═════════════════════════════════════════════════════════════════════════════
# PASO 4 — FUNCIONES LAMBDA
# ═════════════════════════════════════════════════════════════════════════════
step "4" "Funciones Lambda"

deploy_lambda() {
  local FUNC_NAME=$1 ZIP_PATH=$2 ENV_VARS=$3
  if aws lambda get-function --function-name "$FUNC_NAME" &>/dev/null; then
    info "$FUNC_NAME ya existe, actualizando codigo y config..."
    aws lambda update-function-code --function-name "$FUNC_NAME" \
      --zip-file "fileb://$ZIP_PATH" >/dev/null
    # Esperar a que el update de code termine antes de actualizar config
    aws lambda wait function-updated --function-name "$FUNC_NAME"
    aws lambda update-function-configuration --function-name "$FUNC_NAME" \
      --environment "Variables={$ENV_VARS}" --timeout 300 >/dev/null
    ok "$FUNC_NAME actualizada"
  else
    info "Creando Lambda $FUNC_NAME..."
    aws lambda create-function \
      --function-name "$FUNC_NAME" \
      --runtime python3.12 \
      --role "$LAMBDA_ROLE_ARN" \
      --handler lambda_function.lambda_handler \
      --zip-file "fileb://$ZIP_PATH" \
      --timeout 300 \
      --environment "Variables={$ENV_VARS}" >/dev/null
    ok "$FUNC_NAME creada"
  fi
}

# ── Flights ───────────────────────────────────────────────────────────────────
mkdir -p /tmp/lf && cat > /tmp/lf/lambda_function.py << 'PYEOF'
import json, boto3, urllib.request, os
from datetime import datetime
def lambda_handler(event, context):
    bucket  = os.environ['BUCKET_NAME']
    api_key = os.environ['AVIATIONSTACK_API_KEY']
    url = f'http://api.aviationstack.com/v1/flights?access_key={api_key}&limit=100'
    with urllib.request.urlopen(urllib.request.Request(url), timeout=30) as r:
        data = json.loads(r.read().decode('utf-8'))
    key = f"flights/flights_{datetime.utcnow().strftime('%Y-%m-%d_%H-%M-%S')}.json"
    boto3.client('s3').put_object(Bucket=bucket, Key=key,
        Body=json.dumps(data), ContentType='application/json')
    print(f'Guardado: {key}')
    return {'statusCode': 200, 'body': f'OK: {key}'}
PYEOF
cd /tmp/lf && zip -q flights.zip lambda_function.py
deploy_lambda "caso6-flights-extractor" "/tmp/lf/flights.zip" \
  "BUCKET_NAME=$BUCKET_RAW,AVIATIONSTACK_API_KEY=$AVIATIONSTACK_API_KEY"

# ── Weather ───────────────────────────────────────────────────────────────────
mkdir -p /tmp/lw && cat > /tmp/lw/lambda_function.py << 'PYEOF'
import json, boto3, urllib.request, os
from datetime import datetime
def lambda_handler(event, context):
    bucket  = os.environ['BUCKET_NAME']
    api_key = os.environ['WEATHERAPI_KEY']
    city    = os.environ['CITY']
    url = f'http://api.weatherapi.com/v1/current.json?key={api_key}&q={city}&aqi=no'
    with urllib.request.urlopen(urllib.request.Request(url), timeout=30) as r:
        data = json.loads(r.read().decode('utf-8'))
    key = f"weather/weather_{datetime.utcnow().strftime('%Y-%m-%d_%H-%M-%S')}.json"
    boto3.client('s3').put_object(Bucket=bucket, Key=key,
        Body=json.dumps(data), ContentType='application/json')
    print(f'Guardado: {key}')
    return {'statusCode': 200, 'body': f'OK: {key}'}
PYEOF
cd /tmp/lw && zip -q weather.zip lambda_function.py
deploy_lambda "caso6-weather-extractor" "/tmp/lw/weather.zip" \
  "BUCKET_NAME=$BUCKET_RAW,WEATHERAPI_KEY=$WEATHERAPI_KEY,CITY=Medellin"

# ── Delays ────────────────────────────────────────────────────────────────────
mkdir -p /tmp/ld && cat > /tmp/ld/lambda_function.py << 'PYEOF'
import json, boto3, urllib.request, base64, os
from datetime import datetime
def lambda_handler(event, context):
    bucket   = os.environ['BUCKET_NAME']
    user     = os.environ['DELAY_API_USER']
    password = os.environ['DELAY_API_PASS']
    encoded  = base64.b64encode(f'{user}:{password}'.encode()).decode()
    req = urllib.request.Request(
        'https://jsonplaceholder.typicode.com/todos',
        headers={'Authorization': f'Basic {encoded}'}
    )
    with urllib.request.urlopen(req, timeout=30) as r:
        data = json.loads(r.read().decode('utf-8'))
    key = f"delays/delays_{datetime.utcnow().strftime('%Y-%m-%d_%H-%M-%S')}.json"
    boto3.client('s3').put_object(Bucket=bucket, Key=key,
        Body=json.dumps(data), ContentType='application/json')
    print(f'Guardado: {key}')
    return {'statusCode': 200, 'body': f'OK: {key}'}
PYEOF
cd /tmp/ld && zip -q delays.zip lambda_function.py
deploy_lambda "caso6-delay-extractor" "/tmp/ld/delays.zip" \
  "BUCKET_NAME=$BUCKET_RAW,DELAY_API_USER=$DELAY_API_USER,DELAY_API_PASS=$DELAY_API_PASS"

# ═════════════════════════════════════════════════════════════════════════════
# PASO 5 — GLUE ETL
# ═════════════════════════════════════════════════════════════════════════════
step "5" "Glue Job ETL"

cat > /tmp/caso6_etl.py << 'PYEOF'
import sys
from awsglue.transforms import *
from awsglue.utils import getResolvedOptions
from pyspark.context import SparkContext
from awsglue.context import GlueContext
from awsglue.job import Job
from pyspark.sql import functions as F
from pyspark.sql.types import *

args = getResolvedOptions(sys.argv, ['JOB_NAME'])
sc = SparkContext(); glueContext = GlueContext(sc)
spark = glueContext.spark_session
job = Job(glueContext); job.init(args['JOB_NAME'], args)
RAW = 's3://caso6-raw'; PROCESSED = 's3://caso6-processed'

try:
    df = spark.read.option('multiline','true').json(f'{RAW}/flights/')
    df = df.select(F.explode('data').alias('f'))
    df = df.select(
        F.col('f.flight_date').cast(DateType()).alias('flight_date'),
        F.col('f.flight_status').alias('flight_status'),
        F.col('f.departure.airport').alias('departure_airport'),
        F.col('f.departure.iata').alias('departure_iata'),
        F.col('f.departure.scheduled').alias('departure_scheduled'),
        F.col('f.departure.delay').cast(IntegerType()).alias('departure_delay_min'),
        F.col('f.arrival.airport').alias('arrival_airport'),
        F.col('f.arrival.iata').alias('arrival_iata'),
        F.col('f.arrival.scheduled').alias('arrival_scheduled'),
        F.col('f.arrival.delay').cast(IntegerType()).alias('arrival_delay_min'),
        F.col('f.airline.name').alias('airline_name'),
        F.col('f.airline.iata').alias('airline_iata'),
        F.col('f.flight.number').alias('flight_number'),
        F.current_timestamp().alias('ingested_at'))
    df.write.mode('append').partitionBy('flight_date').parquet(f'{PROCESSED}/flights/')
    print(f'Flights OK: {df.count()} registros')
except Exception as e: print(f'ERROR flights: {e}')

try:
    df = spark.read.option('multiline','true').json(f'{RAW}/weather/')
    df = df.select(
        F.col('location.name').alias('city'), F.col('location.region').alias('region'),
        F.col('location.country').alias('country'),
        F.col('location.lat').cast(DoubleType()).alias('latitude'),
        F.col('location.lon').cast(DoubleType()).alias('longitude'),
        F.col('location.localtime').alias('local_time'),
        F.col('current.temp_c').cast(DoubleType()).alias('temp_c'),
        F.col('current.temp_f').cast(DoubleType()).alias('temp_f'),
        F.col('current.humidity').cast(IntegerType()).alias('humidity'),
        F.col('current.wind_kph').cast(DoubleType()).alias('wind_kph'),
        F.col('current.wind_dir').alias('wind_direction'),
        F.col('current.pressure_mb').cast(DoubleType()).alias('pressure_mb'),
        F.col('current.precip_mm').cast(DoubleType()).alias('precip_mm'),
        F.col('current.cloud').cast(IntegerType()).alias('cloud_coverage'),
        F.col('current.vis_km').cast(DoubleType()).alias('visibility_km'),
        F.col('current.condition.text').alias('condition'),
        F.col('current.chance_of_rain').cast(IntegerType()).alias('chance_of_rain'),
        F.to_date(F.col('location.localtime')).alias('weather_date'),
        F.current_timestamp().alias('ingested_at'))
    df.write.mode('append').partitionBy('weather_date').parquet(f'{PROCESSED}/weather/')
    print(f'Weather OK: {df.count()} registros')
except Exception as e: print(f'ERROR weather: {e}')

try:
    df = spark.read.option('multiline','true').json(f'{RAW}/delays/')
    df = df.select(
        F.col('userId').cast(IntegerType()).alias('user_id'),
        F.col('id').cast(IntegerType()).alias('incident_id'),
        F.col('title').alias('incident_title'),
        F.col('completed').cast(BooleanType()).alias('is_resolved'),
        F.current_date().alias('report_date'),
        F.current_timestamp().alias('ingested_at'))
    df.write.mode('append').partitionBy('report_date').parquet(f'{PROCESSED}/delays/')
    print(f'Delays OK: {df.count()} registros')
except Exception as e: print(f'ERROR delays: {e}')

job.commit()
print('caso6-etl completado')
PYEOF

aws s3 cp /tmp/caso6_etl.py "s3://$BUCKET_PROCESSED/scripts/caso6_etl.py" >/dev/null

if aws glue get-job --job-name "caso6-etl" &>/dev/null; then
  info "caso6-etl ya existe, actualizando..."
  aws glue update-job --job-name "caso6-etl" --job-update \
    "Role=$GLUE_ROLE_ARN,\
Command={Name=glueetl,ScriptLocation=s3://$BUCKET_PROCESSED/scripts/caso6_etl.py,PythonVersion=3},\
GlueVersion=4.0,WorkerType=G.1X,NumberOfWorkers=2,\
DefaultArguments={--job-bookmark-option=job-bookmark-enable}" >/dev/null
  ok "caso6-etl actualizado"
else
  aws glue create-job --name "caso6-etl" \
    --role "$GLUE_ROLE_ARN" \
    --command "Name=glueetl,ScriptLocation=s3://$BUCKET_PROCESSED/scripts/caso6_etl.py,PythonVersion=3" \
    --glue-version "4.0" --worker-type "G.1X" --number-of-workers 2 \
    --default-arguments '{"--job-bookmark-option":"job-bookmark-enable"}' >/dev/null
  ok "caso6-etl creado"
fi

# ═════════════════════════════════════════════════════════════════════════════
# PASO 6 — ATHENA WORKGROUP Y DDL
# ═════════════════════════════════════════════════════════════════════════════
step "6" "Athena workgroup y tablas"

aws athena create-work-group \
  --name "caso6-wg" \
  --configuration "ResultConfiguration={OutputLocation=s3://$BUCKET_ATHENA/}" \
  2>/dev/null && ok "Workgroup caso6-wg creado" || ok "Workgroup caso6-wg ya existe"

run_athena() {
  local QUERY=$1 DESC=$2
  info "DDL: $DESC..."
  EXEC_ID=$(aws athena start-query-execution \
    --query-string "$QUERY" --work-group "caso6-wg" \
    --query 'QueryExecutionId' --output text)
  for i in {1..30}; do
    STATUS=$(aws athena get-query-execution --query-execution-id "$EXEC_ID" \
      --query 'QueryExecution.Status.State' --output text)
    [[ "$STATUS" == "SUCCEEDED" ]] && { ok "$DESC"; return; }
    [[ "$STATUS" == "FAILED" ]] && {
      REASON=$(aws athena get-query-execution --query-execution-id "$EXEC_ID" \
        --query 'QueryExecution.Status.StateChangeReason' --output text)
      warn "$DESC: $REASON"
      return
    }
    sleep 3
  done
  warn "$DESC: timeout"
}

run_athena "CREATE DATABASE IF NOT EXISTS caso6_db" "DB caso6_db"

run_athena "CREATE EXTERNAL TABLE IF NOT EXISTS caso6_db.flights (
  flight_status STRING, departure_airport STRING, departure_iata STRING,
  departure_scheduled STRING, departure_delay_min INT, arrival_airport STRING,
  arrival_iata STRING, arrival_scheduled STRING, arrival_delay_min INT,
  airline_name STRING, airline_iata STRING, flight_number STRING, ingested_at TIMESTAMP)
PARTITIONED BY (flight_date DATE) STORED AS PARQUET
LOCATION 's3://caso6-processed/flights/'
TBLPROPERTIES ('parquet.compression'='SNAPPY')" "Tabla flights"

run_athena "CREATE EXTERNAL TABLE IF NOT EXISTS caso6_db.weather (
  city STRING, region STRING, country STRING, latitude DOUBLE, longitude DOUBLE,
  local_time STRING, temp_c DOUBLE, temp_f DOUBLE, humidity INT, wind_kph DOUBLE,
  wind_direction STRING, pressure_mb DOUBLE, precip_mm DOUBLE, cloud_coverage INT,
  visibility_km DOUBLE, condition STRING, chance_of_rain INT, ingested_at TIMESTAMP)
PARTITIONED BY (weather_date DATE) STORED AS PARQUET
LOCATION 's3://caso6-processed/weather/'
TBLPROPERTIES ('parquet.compression'='SNAPPY')" "Tabla weather"

run_athena "CREATE EXTERNAL TABLE IF NOT EXISTS caso6_db.delays (
  user_id INT, incident_id INT, incident_title STRING,
  is_resolved BOOLEAN, ingested_at TIMESTAMP)
PARTITIONED BY (report_date DATE) STORED AS PARQUET
LOCATION 's3://caso6-processed/delays/'
TBLPROPERTIES ('parquet.compression'='SNAPPY')" "Tabla delays"

# ═════════════════════════════════════════════════════════════════════════════
# PASO 7 — GLUE DBT RUNNER
# ═════════════════════════════════════════════════════════════════════════════
step "7" "Glue Python Shell — dbt runner"

cat > /tmp/caso6_dbt_runner.py << 'PYEOF'
import subprocess, sys, os
print('=== caso6-dbt-runner iniciando ===')
subprocess.check_call([sys.executable, '-m', 'pip', 'install',
    'dbt-athena-community==1.7.3', 'boto3', '--quiet'])
subprocess.check_call(['aws', 's3', 'sync',
    's3://caso6-processed/dbt-project/', '/tmp/dbt_project/', '--quiet'])
os.makedirs('/tmp/dbt_profiles', exist_ok=True)
with open('/tmp/dbt_profiles/profiles.yml', 'w') as f:
    f.write("""dbt_airline:
  target: prod
  outputs:
    prod:
      type: athena
      region_name: us-east-1
      s3_staging_dir: s3://caso6-athena-results/dbt/
      schema: caso6_db
      database: awsdatacatalog
      threads: 4
      work_group: caso6-wg
""")
os.chdir('/tmp/dbt_project')
r = subprocess.run(['dbt','run','--profiles-dir','/tmp/dbt_profiles',
    '--project-dir','/tmp/dbt_project','--no-use-colors'],
    capture_output=True, text=True)
print(r.stdout)
if r.returncode != 0:
    print(r.stderr); raise Exception(f'dbt run fallo: {r.returncode}')
rt = subprocess.run(['dbt','test','--profiles-dir','/tmp/dbt_profiles',
    '--project-dir','/tmp/dbt_project','--no-use-colors'],
    capture_output=True, text=True)
print(rt.stdout)
print('=== caso6-dbt-runner completado ===')
PYEOF

aws s3 cp /tmp/caso6_dbt_runner.py "s3://$BUCKET_PROCESSED/scripts/caso6_dbt_runner.py" >/dev/null

if aws glue get-job --job-name "caso6-dbt-runner" &>/dev/null; then
  info "caso6-dbt-runner ya existe, actualizando..."
  aws glue update-job --job-name "caso6-dbt-runner" --job-update \
    "Role=$GLUE_ROLE_ARN,\
Command={Name=pythonshell,ScriptLocation=s3://$BUCKET_PROCESSED/scripts/caso6_dbt_runner.py,PythonVersion=3.9},\
MaxCapacity=0.0625" >/dev/null
  ok "caso6-dbt-runner actualizado"
else
  aws glue create-job --name "caso6-dbt-runner" \
    --role "$GLUE_ROLE_ARN" \
    --command "Name=pythonshell,ScriptLocation=s3://$BUCKET_PROCESSED/scripts/caso6_dbt_runner.py,PythonVersion=3.9" \
    --max-capacity 0.0625 >/dev/null
  ok "caso6-dbt-runner creado"
fi

# ═════════════════════════════════════════════════════════════════════════════
# PASO 8 — STEP FUNCTIONS
# ═════════════════════════════════════════════════════════════════════════════
step "8" "Step Functions"

SFN_ARN="arn:aws:states:${AWS_REGION}:${ACCOUNT_ID}:stateMachine:caso6-pipeline"

STATE_MACHINE_DEF=$(cat << 'SFNJSON'
{
  "Comment": "Pipeline diario Caso 6",
  "StartAt": "IngestData",
  "States": {
    "IngestData": {
      "Type": "Parallel",
      "Branches": [
        {"StartAt":"FlightsLambda","States":{"FlightsLambda":{"Type":"Task","Resource":"arn:aws:states:::lambda:invoke","Parameters":{"FunctionName":"caso6-flights-extractor","Payload":{}},"Retry":[{"ErrorEquals":["States.ALL"],"IntervalSeconds":30,"MaxAttempts":2}],"End":true}}},
        {"StartAt":"WeatherLambda","States":{"WeatherLambda":{"Type":"Task","Resource":"arn:aws:states:::lambda:invoke","Parameters":{"FunctionName":"caso6-weather-extractor","Payload":{}},"Retry":[{"ErrorEquals":["States.ALL"],"IntervalSeconds":30,"MaxAttempts":2}],"End":true}}},
        {"StartAt":"DelayLambda","States":{"DelayLambda":{"Type":"Task","Resource":"arn:aws:states:::lambda:invoke","Parameters":{"FunctionName":"caso6-delay-extractor","Payload":{}},"Retry":[{"ErrorEquals":["States.ALL"],"IntervalSeconds":30,"MaxAttempts":2}],"End":true}}}
      ],
      "Next": "RunGlueETL"
    },
    "RunGlueETL": {
      "Type": "Task",
      "Resource": "arn:aws:states:::glue:startJobRun.sync",
      "Parameters": {"JobName": "caso6-etl"},
      "Retry": [{"ErrorEquals":["States.ALL"],"IntervalSeconds":60,"MaxAttempts":1}],
      "Next": "RepairAthena"
    },
    "RepairAthena": {
      "Type": "Task",
      "Resource": "arn:aws:states:::athena:startQueryExecution.sync",
      "Parameters": {
        "QueryString": "MSCK REPAIR TABLE caso6_db.flights",
        "WorkGroup": "caso6-wg",
        "ResultConfiguration": {"OutputLocation": "s3://caso6-athena-results/repair/"}
      },
      "Next": "RunDbt"
    },
    "RunDbt": {
      "Type": "Task",
      "Resource": "arn:aws:states:::glue:startJobRun.sync",
      "Parameters": {"JobName": "caso6-dbt-runner"},
      "Retry": [{"ErrorEquals":["States.ALL"],"IntervalSeconds":60,"MaxAttempts":1}],
      "End": true
    }
  }
}
SFNJSON
)

if aws stepfunctions describe-state-machine --state-machine-arn "$SFN_ARN" &>/dev/null; then
  info "State Machine ya existe, actualizando definicion..."
  aws stepfunctions update-state-machine \
    --state-machine-arn "$SFN_ARN" \
    --definition "$STATE_MACHINE_DEF" \
    --role-arn "$SFN_ROLE_ARN" >/dev/null
  ok "State Machine actualizada"
else
  SFN_ARN=$(aws stepfunctions create-state-machine \
    --name "caso6-pipeline" \
    --definition "$STATE_MACHINE_DEF" \
    --role-arn "$SFN_ROLE_ARN" \
    --type STANDARD \
    --query 'stateMachineArn' --output text)
  ok "State Machine creada: $SFN_ARN"
fi

# ═════════════════════════════════════════════════════════════════════════════
# PASO 9 — EVENTBRIDGE SCHEDULER
# ═════════════════════════════════════════════════════════════════════════════
step "9" "EventBridge Scheduler"

# Verificar si ya existe el schedule
if aws scheduler get-schedule --name "caso6-daily-noon" &>/dev/null; then
  info "Schedule ya existe, actualizando..."
  aws scheduler update-schedule \
    --name "caso6-daily-noon" \
    --schedule-expression "cron(0 17 * * ? *)" \
    --schedule-expression-timezone "America/Bogota" \
    --target "{\"Arn\":\"$SFN_ARN\",\"RoleArn\":\"$EB_ROLE_ARN\",\"Input\":\"{}\"}" \
    --flexible-time-window '{"Mode":"OFF"}' >/dev/null
  ok "Schedule actualizado"
else
  aws scheduler create-schedule \
    --name "caso6-daily-noon" \
    --schedule-expression "cron(0 17 * * ? *)" \
    --schedule-expression-timezone "America/Bogota" \
    --target "{\"Arn\":\"$SFN_ARN\",\"RoleArn\":\"$EB_ROLE_ARN\",\"Input\":\"{}\"}" \
    --flexible-time-window '{"Mode":"OFF"}' \
    --action-after-completion NONE >/dev/null
  ok "Schedule creado: 12:00 PM Bogota diario"
fi

# ═════════════════════════════════════════════════════════════════════════════
# RESUMEN
# ═════════════════════════════════════════════════════════════════════════════
echo ""
echo -e "${BOLD}${GREEN}╔══════════════════════════════════════════════════╗${NC}"
echo -e "${BOLD}${GREEN}║       DEPLOY COMPLETADO EXITOSAMENTE             ║${NC}"
echo -e "${BOLD}${GREEN}╚══════════════════════════════════════════════════╝${NC}"
echo ""
echo -e "${BOLD}Infraestructura:${NC}"
echo -e "  VPC          ${CYAN}$VPC_ID${NC}   Subredes: ${CYAN}$SUBNET_A_ID${NC} / ${CYAN}$SUBNET_B_ID${NC}"
echo -e "  S3 raw       ${CYAN}s3://$BUCKET_RAW${NC}"
echo -e "  S3 processed ${CYAN}s3://$BUCKET_PROCESSED${NC}"
echo -e "  S3 curated   ${CYAN}s3://$BUCKET_CURATED${NC}"
echo ""
echo -e "${BOLD}Siguiente paso obligatorio — sube el proyecto dbt:${NC}"
echo -e "  ${YELLOW}aws s3 sync airline/dbt_airline/ s3://caso6-processed/dbt-project/ --delete${NC}"
echo ""
echo -e "${BOLD}Prueba el pipeline completo:${NC}"
echo -e "  ${YELLOW}aws stepfunctions start-execution --state-machine-arn $SFN_ARN --input '{}'${NC}"
echo ""
echo -e "${BOLD}Verifica los datos en Athena:${NC}"
echo -e "  ${YELLOW}aws athena start-query-execution \\${NC}"
echo -e "  ${YELLOW}  --query-string 'SELECT * FROM caso6_db.fct_flights_analytics LIMIT 10' \\${NC}"
echo -e "  ${YELLOW}  --work-group caso6-wg \\${NC}"
echo -e "  ${YELLOW}  --query QueryExecutionId --output text${NC}"
echo ""
