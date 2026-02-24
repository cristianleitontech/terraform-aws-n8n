# Terraform: n8n en AWS Free Tier

Esta receta crea la infraestructura para ejecutar n8n en AWS y ahora incluye una forma segura y barata de manejar el estado de Terraform en remoto usando S3 (sin guardar `tfstate` en GitHub ni depender del disco local de una sola laptop).

## Arquitectura

- **VPC nueva** (`/16`) con una subred pública `/24`, Internet Gateway y tabla de rutas dedicada.
- **Security Group** que solo permite tráfico HTTP/HTTPS desde cualquier origen; no se expone SSH porque la administración se realiza con AWS Systems Manager Session Manager.
- **Rol de servicio SSM** (`AWSServiceRoleForAmazonSSM`) creado automáticamente para que la cuenta registre instancias como Managed Instances sin pasos manuales.
- **EC2 t3.micro** con disco raíz gp3 de 30 GiB, Elastic IP fija e IAM Instance Profile con la política `AmazonSSMManagedInstanceCore`.
- **Volumen EBS adicional (20 GiB gp3, cifrado)** montado en `/opt/n8n` con `delete_on_termination = false`.
- **EventBridge + SSM Automation** que apaga la instancia a las 02:00 y la enciende a las 06:00 (equivalente `America/Bogota`, definido como cron UTC en `main.tf`).
- **Instalación automática** vía cloud-init de Docker + Docker Compose, despliegue de `n8nio/n8n:latest` y `caddy:2.7-alpine`, Basic Auth obligatoria y clave de cifrado de n8n generada por Terraform.

## Backend remoto de Terraform (recomendado)

### Qué resuelve

- Evita que el estado viva solo en tu PC.
- Permite operar el mismo stack desde varios equipos.
- Evita subir `terraform.tfstate` a GitHub.
- Mantiene costo bajo para proyecto personal (S3 + versionado).

### Diseño aplicado

- Backend `s3` en `backend.tf`.
- Bloqueo nativo con `use_lockfile = true`.
- Cifrado habilitado (`encrypt = true`).
- Bucket creado con un stack de bootstrap separado en `bootstrap/state-backend/`.

## Requisitos

1. Terraform >= 1.5.
2. Credenciales AWS configuradas (`aws configure` o variables de entorno).
3. Permisos para EC2, VPC, IAM, EventBridge/CloudWatch Events, SSM Automation y S3.
4. Control sobre el dominio raíz en Namecheap para crear registros DNS.

## Paso 1: crear bucket de state (bootstrap)

Desde la raíz del proyecto:

```bash
cd bootstrap/state-backend
terraform init
terraform apply -var='bucket_name=TU_BUCKET_UNICO_DE_STATE'
```

Notas:
- El nombre del bucket S3 debe ser globalmente único.
- Este módulo configura: versionado, cifrado SSE-S3 (`AES256`), bloqueo de acceso público y lifecycle para limpiar versiones no actuales.

## Paso 2: configurar backend del stack principal

Vuelve a la raíz del proyecto:

```bash
cd ../..
cp backend.hcl.example backend.hcl
```

Edita `backend.hcl` y define el bucket real:

```hcl
bucket = "TU_BUCKET_UNICO_DE_STATE"
```

`backend.hcl` está en `.gitignore` para no subir configuración local.

## Paso 3: migrar state local a remoto

Si ya tienes `terraform.tfstate` local en este proyecto:

```bash
terraform init -reconfigure -backend-config=backend.hcl
```

Terraform te preguntará si quieres migrar el state local al backend remoto. Responde `yes`.

Después valida:

```bash
terraform state list
```

Si todo quedó correcto, puedes eliminar copias locales viejas del state:

```bash
rm -f terraform.tfstate terraform.tfstate.backup
```

## Uso normal después de la migración

```bash
terraform plan
terraform apply
```

Para usarlo en otro PC:

1. Clona el repo.
2. Configura credenciales AWS.
3. Crea tu `backend.hcl` local con el mismo bucket.
4. Crea tus variables locales:

```bash
cp terraform.tfvars.example terraform.tfvars
```

Completa en `terraform.tfvars` al menos `root_domain`, `subdomain`, `n8n_basic_auth_user` y `n8n_basic_auth_password`.

5. Ejecuta:

```bash
terraform init -reconfigure -backend-config=backend.hcl
terraform plan
```

## Despliegue de infraestructura n8n

1. Copia el archivo de ejemplo de variables:

```bash
cp terraform.tfvars.example terraform.tfvars
```

2. Ajusta al menos:
- `root_domain`: por ejemplo `example.com`
- `subdomain`: por ejemplo `n8n-demo`
- `n8n_basic_auth_user` y `n8n_basic_auth_password`
- `letsencrypt_email` (opcional pero recomendado)

3. Ejecuta:

```bash
terraform plan
terraform apply
```

4. Crea el registro DNS tipo A en Namecheap:
- Host: usa el mismo valor de `subdomain` (por ejemplo `n8n-demo`)
- Valor: output `instance_public_ip`
- TTL: Automatic o 5 minutos

Luego accede a `https://<subdomain>.<tu-dominio>`.

## Operación

- Conexión por Session Manager:

```bash
aws ssm start-session --target <instance-id>
```

- Ajustar horario de apagado/encendido automático: editar `aws_cloudwatch_event_rule.stop_instance` y `aws_cloudwatch_event_rule.start_instance` en `main.tf`.
- Actualizar contenedores:

```bash
cd /opt/n8n
docker compose pull
docker compose up -d
```

- Antes de cambios mayores o `terraform destroy`, hacer snapshot del volumen EBS (`data_volume_id`).

## Archivos relevantes

- `main.tf`: infraestructura principal de n8n.
- `variables.tf`: parámetros del stack principal.
- `outputs.tf`: salidas del stack principal.
- `backend.tf`: configuración del backend remoto S3.
- `backend.hcl.example`: plantilla local para el bucket del backend.
- `bootstrap/state-backend/main.tf`: módulo bootstrap del bucket S3 de state.
- `scripts/user-data.sh.tftpl`: bootstrap de instancia (Docker, n8n, Caddy).
