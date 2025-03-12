#!/bin/bash

#Creado por: DEVSECOPS 
#Proyecto: catalys GCP
#Autor: esllanesb

set -x

DATEEXEC=$(date +"%Y%m%d%H%M")
WORK_DIR=/root
LOG_EJECUCION_SCRIPT="$WORK_DIR/script_inicio_${DATEEXEC}.log"
LOCK_FILE_EJECUCION_SCRIPT="$WORK_DIR/estado_ejecucion.lock"

#Obtencion de metadata de la computer engine
AMBIENTE=$(curl http://metadata.google.internal/computeMetadata/v1/instance/attributes/ambiente -H "Metadata-Flavor: Google")
APP=$(curl http://metadata.google.internal/computeMetadata/v1/instance/attributes/app -H "Metadata-Flavor: Google")
ZONE=$(curl http://metadata.google.internal/computeMetadata/v1/instance/zone -H "Metadata-Flavor: Google" | awk -F '/' '{print $4}')

if [ -z "$AMBIENTE" ] || [ -z "$APP" ] || [ -z "$ZONE" ]; then
    echo "Error: No se encuentra definida en la metadata de la computer engine uno de estos atributos: AMBIENTE, APP o ZONE"
	log_a_bucket
    exit 1
fi

export APP=${APP}
export AMBIENTE=${AMBIENTE}

#Buckets de aprovisionamiento de instalables e script de inicio
export APP_BUCKET=gs://iuse${AMBIENTE}gcpcscommoncatalys01/catalys/install
export APP_BUCKET_BACKUPS=gs://iuse${AMBIENTE}gcpcscommoncatalys01/catalys/backups/

#hostname del nodo y el mis en la red privada GCP
APP_CATALYS_HOSTNAME_NODE="luse${AMBIENTE}gcpvmcatalyscore01"
APP_CATALYS_HOSTNAME_MIS="luse${AMBIENTE}gcpvmcatalysmis01"

#directorios base de la instalacion catalys
APPS_CATALYS_SYMLINK_DIR=/usr/local/bin
APPS_CATALYS_DIR_BASE=/usr/local
APPS_CATALYS_DIR=$APPS_CATALYS_DIR_BASE/CameronTec

#directorios de instalacion  de los componentes catalys
APP_CATALYS_DIR=$APPS_CATALYS_DIR/${APP}
APP_CATALYS_DIR_INSTANCE=$APPS_CATALYS_DIR/catalys-node-instance
APP_CATALYS_DIR_LMA=$APPS_CATALYS_DIR/catalys-lma
APP_CATALYS_DIR_MIS=$APPS_CATALYS_DIR/catalys-mis-2.2

#Expersion regular para detectar scripts de inicio de sesion
APP_NODE_INSTANCE_SESION_SCRIPTS="${APP_CATALYS_DIR_INSTANCE}/sesiones/scripts/start-sesion*"

#Path del archivo de configuracion del mis
APP_MIS_CONFIG_DIR_FILE="${APP_CATALYS_DIR_MIS}/conf/mis.conf"

#directorios de instalables y configuraciones de instalacion
CONFIG_FILE_EJECUCION_SCRIPT="deploy_config.properties"
APP_CATALYS_NODE_INSTALLER_SHELL=catalys-node-2.2-installer-ra9e05de1.sh
APP_CATALYS_NODE_INSTALLER_PACKAGE=catalys-node-2.2-package-ra9e05de1.zip
APP_CATALYS_NODE_INSTALLER_INSTANCE_PACKAGE=catalys-node-instance.zip

APP_CATALYS_LMA_INSTALLER_SHELL=catalys-lma-2.2-installer-rfd7d8890.sh
APP_CATALYS_LMA_INSTALLER_PACKAGE=catalys-lma-2.2-package-rfd7d8890.zip
APP_CATALYS_LMA_INSTALLER_CONF=config-LMA-installer.varfile

APP_CATALYS_MIS_INSTALLER_SHELL=catalys-mis-2.2-installer-re81244c7.sh
APP_CATALYS_MIS_INSTALLER_CONF=config-MIS-installer.varfile

#Definicion de secret manager del ambiente
GCPPROJECT_SECRETMANAGER=bch-prj-common-infra-qa-dcae

#archivos y directorios de licencia de catalys
APP_LICENSE_SECRET=catalys-${AMBIENTE}-license
APP_LICENSE_FILE="camerontec_license.xml"
APPS_LICENSE_FILE_PATH="$WORK_DIR/$APP_LICENSE_FILE"

#manejo de secreto de datos de conexion de sesiones fix
APP_NODE_INSTANCE_SESION_CONFIG_SECRET=catalys-${AMBIENTE}-sesiones-conf
APP_NODE_INSTANCE_SESION_CONFIG_FILE="sesiones-conf.properties"
APP_NODE_INSTANCE_SESION_CONFIG_DIR="${APP_CATALYS_DIR_INSTANCE}/sesiones/conf/${APP_NODE_INSTANCE_SESION_CONFIG_FILE}"
APP_NODE_INSTANCE_SESION_LOG_DIR="${APP_CATALYS_DIR_INSTANCE}/sesiones/logs"

#certificado y keystore para sesion bloomberg
APP_NODE_INSTANCE_SESION_BLOOMBERG_JKS_SECRET=catalys-${AMBIENTE}-sesion-bloom-jks
APP_NODE_INSTANCE_SESION_BLOOMBERG_JKS_FILE=cert.jks
APP_NODE_INSTANCE_SESION_BLOOMBERG_JKS_DIR="${APP_CATALYS_DIR_INSTANCE}/sesiones/conf/${APP_NODE_INSTANCE_SESION_BLOOMBERG_JKS_FILE}"

APP_NODE_INSTANCE_SESION_BLOOMBERG_KEYST_SECRET=catalys-${AMBIENTE}-sesion-bloom-keystore
APP_NODE_INSTANCE_SESION_BLOOMBERG_KEYST_FILE=client.keystore
APP_NODE_INSTANCE_SESION_BLOOMBERG_KEYST_DIR="${APP_CATALYS_DIR_INSTANCE}/sesiones/conf/${APP_NODE_INSTANCE_SESION_BLOOMBERG_KEYST_FILE}"

#configuraciones monitoreo
DYNATRACE_SECRET=catalys-${AMBIENTE}-dynatrace
DYNATRACE_FILE="dynatrace.properties"
DYNATRACE_DIR="$WORK_DIR/$DYNATRACE_FILE"

ONEAGENT_HOST_GROUP="GCP-${ZONE}-${AMBIENTE}-catalys"
ONEAGENT_PACKAGE="Dynatrace-OneAgent-Linux.sh"
ONEAGENT_URL_PEM="https://ca.dynatrace.com/dt-root.cert.pem"
ONEAGENT_CMD="/opt/dynatrace/oneagent/agent/tools/oneagentctl"
ONEAGENT_SEGURITY_FILTER_DIR="/var/lib/dynatrace/oneagent/agent/config/logmodule"
ONEAGENT_SEGURITY_FILTER_CONFIG_FILE="${ONEAGENT_SEGURITY_FILTER_DIR}/securitycustomlogs.json"
ONEAGENT_HOST_ID=""

# expresiones regulares para dynatrace de directorios logs de los componentes catalys
APP_CATALYS_DIR_MIS_LOG="$APP_CATALYS_DIR_MIS/logs/catalys-mis.log"
APP_CATALYS_DIR_LMA_LOG="$APP_CATALYS_DIR_LMA/logs/catalys-lma.log"
APP_CATALYS_DIR_INSTANCE_MAIN_LOG="${APP_CATALYS_DIR_INSTANCE}/sesiones/logs/*.log"
APP_CATALYS_DIR_INSTANCE_PERS_LOG="${APP_CATALYS_DIR_INSTANCE}/sesiones/data/persistence/*Msg/journal.*.dat"
#APP_CATALYS_DIR_INSTANCE_HPL_LOG="${APP_CATALYS_DIR_INSTANCE}/sesiones/logs/hpl/*.log*"
APP_CATALYS_DIR_INSTANCE_ARCHIVE_LOG="${APP_CATALYS_DIR_INSTANCE}/sesiones/logs/archive/*.log*"

#Backups
export BACKUP_DIR="$WORK_DIR/backups"
export BACKUP_FILE="$BACKUP_DIR/${APP}-${AMBIENTE}-BKUP.tar.gz"
export BACKUP_FILE_NODE_INSTANCE="$BACKUP_DIR/catalys-node-instance-${AMBIENTE}-BKUP.tar.gz"
export BACKUP_FILE_LMA="$BACKUP_DIR/catalys-lma-${AMBIENTE}-BKUP.tar.gz"
export BACKUP_FILE_MIS="$BACKUP_DIR/catalys-mis-${AMBIENTE}-BKUP.tar.gz"
export BACKUP_FILE_LOG="$BACKUP_DIR/${DATEEXEC}-${APP}-${AMBIENTE}-BKUP-LOG.tar.gz"

#variables de entorno con los path a los aplicativos para ser usadas en login con root en la VM  y ejecucion de script de sesiones fix
export APP_CATALYS_DIR=${APP_CATALYS_DIR}
export APP_CATALYS_DIR_INSTANCE=${APP_CATALYS_DIR_INSTANCE}
export APP_CATALYS_DIR_LMA=${APP_CATALYS_DIR_LMA}
export APP_CATALYS_DIR_MIS=${APP_CATALYS_DIR_MIS}
export CAMERON_LICENSE_ROOTDIR=${APPS_CATALYS_DIR}
export APP_NODE_INSTANCE_SESION_CONFIG_DIR=${APP_NODE_INSTANCE_SESION_CONFIG_DIR}
export APP_NODE_INSTANCE_SESION_LOG_DIR=${APP_NODE_INSTANCE_SESION_LOG_DIR}

ENV_SCRIPT="/etc/profile.d/varsenvironment.sh"
echo '#!/bin/bash' > $ENV_SCRIPT
echo "export APP_CATALYS_DIR=\"$APP_CATALYS_DIR\"" >> $ENV_SCRIPT
echo "export APP_CATALYS_DIR_INSTANCE=\"$APP_CATALYS_DIR_INSTANCE\"" >> $ENV_SCRIPT
echo "export CAMERON_LICENSE_ROOTDIR=\"$CAMERON_LICENSE_ROOTDIR\"" >> $ENV_SCRIPT
echo "export APP_NODE_INSTANCE_SESION_CONFIG_DIR=\"$APP_NODE_INSTANCE_SESION_CONFIG_DIR\"" >> $ENV_SCRIPT
echo "export APP_NODE_INSTANCE_SESION_LOG_DIR=\"$APP_NODE_INSTANCE_SESION_LOG_DIR\"" >> $ENV_SCRIPT
echo "export APP=\"$APP\"" >> $ENV_SCRIPT
echo "export AMBIENTE=\"$AMBIENTE\"" >> $ENV_SCRIPT



#***************************************************************************************************
#***************************************************************************************************
#FUNCIONES
#***************************************************************************************************
#***************************************************************************************************


#log a bucket
function log_a_bucket() {

	gsutil cp $LOG_EJECUCION_SCRIPT $APP_BUCKET_BACKUPS
	journalctl  -u  google-startup-scripts.service --no-pager>$WORK_DIR/journal_${AMBIENTE}_${DATEEXEC}.log
	gsutil cp $WORK_DIR/journal_${AMBIENTE}_${DATEEXEC}.log $APP_BUCKET_BACKUPS

}

# Descargar archivo desde bucket de GCP
function descargar_desde_bucket() {
    local archivo=$1
 	if gsutil stat $APP_BUCKET/$archivo &> /dev/null; then
		echo "INFO: El archivo existe en el bucket. Copiando..." >> "$LOG_EJECUCION_SCRIPT"
		if gsutil cp $APP_BUCKET/$archivo $WORK_DIR >> "$LOG_EJECUCION_SCRIPT"; then
			echo "INFO: Archivo copiado correctamente desde el bucket." >> "$LOG_EJECUCION_SCRIPT"
		else
			echo "ERROR: Fallo al copiar el archivo aplicacion desde el bucket." >> "$LOG_EJECUCION_SCRIPT"
			log_a_bucket
			exit 1
		fi
	else
	  echo "ERROR: El archivo de la aplicacion no existe en el bucket." >> "$LOG_EJECUCION_SCRIPT"
	  log_a_bucket
	  exit 1
	fi
}

# Validar existencia de archivo en local
function validar_archivo() {
    local archivo=$1
	if ! ls $WORK_DIR/${archivo} > /dev/null; then
		echo "ERROR:No se encuentra el archivo ${archivo} " >>"$LOG_EJECUCION_SCRIPT" 
		log_a_bucket
		exit 1
	fi
}

# Respaldo de aplicacion en bucket externo
function respaldar() {
	local directorio_respladar=$1
	local archivo_backup=$2
	
	mkdir -p $BACKUP_DIR
	
	if [ -d "${directorio_respladar}" ]; then
		mkdir -p "$BACKUP_DIR" >>"$LOG_EJECUCION_SCRIPT"
		if tar --ignore-failed-read -czf "${archivo_backup}" --directory="$(dirname "${directorio_respladar}")" "$(basename "${directorio_respladar}")" ; then
			echo "INFO: Directorio existente respaldado exitosamente." >>"$LOG_EJECUCION_SCRIPT"
			gsutil cp $archivo_backup $APP_BUCKET_BACKUPS >>"$LOG_EJECUCION_SCRIPT"
			echo "INFO: Directorio existente respaldado exitosamente en bucket." >>"$LOG_EJECUCION_SCRIPT"
			echo "INFO: Eliminando todo backup local en la instancia, de la aplicacion y de logs." >>"$LOG_EJECUCION_SCRIPT"
			rm -rf $BACKUP_DIR/*BKUP*.tar.gz >>"$LOG_EJECUCION_SCRIPT"
		else
			echo "ERROR: Fallo al crear un respaldo del directorio existente." >>"$LOG_EJECUCION_SCRIPT"
			log_a_bucket
			exit 1
		fi
	fi
}

#Obtencion de secretos de la APP
function obtener_secreto() {
	echo "================================================================================"  >>"$LOG_EJECUCION_SCRIPT"
	echo "INFO:Obteniendo Secretos"  >>"$LOG_EJECUCION_SCRIPT"  

	echo "INFO:Obteniendo Secretos:Generando directorio destino $2"  >>"$LOG_EJECUCION_SCRIPT"  

	if ! gcloud secrets versions access latest --secret=$1 --project=${GCPPROJECT_SECRETMANAGER} --out-file=$2 >> "$LOG_EJECUCION_SCRIPT" 2>&1; then
		echo "ERROR: El comando gcloud fallo al obtener $1"
		log_a_bucket
		exit 1
	fi
	
	echo "================================================================================"  >>"$LOG_EJECUCION_SCRIPT"
	echo "INFO:validacion_Secretos en local"  >>"$LOG_EJECUCION_SCRIPT" 

	if ! ls $2 > /dev/null; then
	  echo "ERROR:No se encuentra $2 ." >>"$LOG_EJECUCION_SCRIPT" 
	  log_a_bucket
	  exit 1
	fi
	
	#permisos exclusivos solo para el usuario 
	chmod 600 $2
}

#Para facilitar lectura de log de ejecucion: se mueven al directorio backups los logs antiguos de journal y de start del script de inicio.
function mover_logs_antiguos(){

	echo "INFO:Moviendo logs antiguos de ejecucion al directorio backups" >>"$LOG_EJECUCION_SCRIPT" 
	
	# Lista de archivos que coinciden con los patrones "journal*" y "script*"
	archivos_journal=$(ls -t /root/journal*)
	archivos_script=$(ls -t /root/script*)

	# Excluye el archivo mas reciente de cada lista
	archivos_a_mover_journal=$(echo "${archivos_journal}" | tail -n +2)
	archivos_a_mover_script=$(echo "${archivos_script}" | tail -n +2)

	mkdir -p $BACKUP_DIR
	# Mueve los archivos restantes al directorio de destino
	for archivo in ${archivos_a_mover_journal} ${archivos_a_mover_script}; do
		mv "${archivo}" "$BACKUP_DIR"
	done
}

#configuracion via API en dynatrace
function api-dynatrace() {
	local schemaId=$1
	local oneagent_host_id=$2
	local config_item_title=$3
	local log_source_path=$4
	local output_curl=$(mktemp)
	
	echo "ERROR:Dynatrace: EsquemaId $schemaId"  >>"$LOG_EJECUCION_SCRIPT"
	
	case $schemaId in

	  "builtin:logmonitoring.custom-log-source-settings")
	  
		# Crear JSON payload
		read -r -d '' PAYLOAD << EOM
[
  {
    "schemaId": "$schemaId",
    "scope": "HOST-${oneagent_host_id}",
    "value": {
        "enabled": true,
        "config-item-title": "$config_item_title",
        "custom-log-source": {
          "type": "LOG_PATH_PATTERN",
		  "accept-binary": true,
          "values-and-enrichment": [
            {
              "path": "$log_source_path",
              "enrichment": [
				{
				  "type": "attribute",
				  "key": "log.file.path",
				  "value": "\${0}"
				}
			  ]
            }
          ]
        },
        "context": []
    }
  }  
]
EOM
	  ;;

	  "builtin:logmonitoring.log-storage-settings")
	
		# Crear JSON payload
		read -r -d '' PAYLOAD << EOM
[
  {
    "schemaId": "$schemaId",
    "scope": "HOST-${oneagent_host_id}",
    "value": {
      "config-item-title": "$config_item_title",
      "send-to-storage": true,
      "matchers": [
        {
          "attribute": "log.source",
          "operator": "MATCHES",
          "values": ["$log_source_path"]
        }
      ],
     "enabled": true
    }
  }
]
EOM
	  ;;

	  *)
		echo "ERROR:Dynatrace: EsquemaId invalido"  >>"$LOG_EJECUCION_SCRIPT"
		;;
	esac

	# POST configuracion a Dynatrace
	HTTP_CODE=$(curl -X POST "$ONEAGENT_API_URL" \
		 -H "Authorization: Api-Token ${ONEAGENT_API_SETTING_TOKEN}" \
		 -H "Content-Type: application/json" \
		 -d "$PAYLOAD"  \
		 -w "%{http_code}" -i -s -S -a --output "$output_curl")
		 
	  if [[ ${HTTP_CODE} -lt 200 || ${HTTP_CODE} -gt 299 ]] ; then
		echo "================================================================================"  >>"$LOG_EJECUCION_SCRIPT"
		echo "ERROR:Dynatrace: Error en configuracion de custom source log"  >>"$LOG_EJECUCION_SCRIPT"
	  else
		echo "================================================================================"  >>"$LOG_EJECUCION_SCRIPT"	 
		echo "INFO:Dynatrace configuracion $schemaId ,item $config_item_title, path $log_source_path"  >>"$LOG_EJECUCION_SCRIPT"
	  fi
	  cat $output_curl >>"$LOG_EJECUCION_SCRIPT"
	  rm $output_curl
}

#modos y estados para la ejecucion del script de inicio. Se basa en cnfiguracion leida en el bucekt y en la VM
function definir_modo_y_estado() {
    local mode="$1"
    local version="$2"
    local last_action="$3"
    local last_version="$4"
    local last_mode="$5"

    case $mode in
        "inicial")
            if [[ "$last_action" == "ninguna" ]]; then
                #echo "Despliegue inicial permitido para modo $mode."
                echo "inicial_completed $mode $version"
            else
                #echo "Despliegue inicial ya completado previamente. No se realizara accion."
                echo "skip skip skip"
            fi
            ;;
        "inicial-forzado")
            #echo "Despliegue inicial forzado para modo $mode."
            echo "inicial_completed $mode $version"
            ;;
        "update")
            if [[ "$last_action" == "inicial_completed" || "$last_action" == "update_completed" ]]; then
                if [[ "$last_version" == "$version" ]]; then
                    #echo "La version $version ya esta instalada. No se realizara accion."
                    echo "skip skip skip"
                else
                    #echo "Actualizacion permitida a la version $version."
                    echo "update_completed $mode $version"
                fi
            else
                #echo "No se puede realizar actualizacion: falta despliegue inicial previo."
                echo "skip skip skip"
            fi
            ;;
        *)
            #echo "Modo desconocido: $mode. No se realizara accion."
            echo "skip skip skip"
            ;;
    esac
}

#registra el estado de ejecucion efectivo del script en la VM
function registrar_estado() {
    local accion="$1"
    local modo="$2"
    local version="$3"
    local timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

    if [[ "$accion" == "skip" ]]; then
        echo "No se registrara ningun estado." | tee -a "$LOG_EJECUCION_SCRIPT"
    else
        cat <<EOF > "${LOCK_FILE_EJECUCION_SCRIPT}"
last_action=$accion
last_mode=$modo
last_version=$version
timestamp=$timestamp
EOF
        echo "Estado registrado: Accion=$accion, Modo=$modo, Version=$version, Timestamp=$timestamp" | tee -a "$LOG_EJECUCION_SCRIPT"
    fi
}

#instalar paquetes
function instalar_paquetes() {

	echo "================================================================================"  >>"$LOG_EJECUCION_SCRIPT"
	echo "INFO:Inicio_instalacion_paquetes"  >>"$LOG_EJECUCION_SCRIPT"  

	packages=("nano" "wget" "telnet" "unzip" "java-1.8.0-openjdk" "policycoreutils-python-utils")

	# Iterar sobre los paquetes y verificar si estan instalados
	for package in "${packages[@]}"
	do
		if ! rpm -q $package &> /dev/null
		then
			yum install -y $package >>"$LOG_EJECUCION_SCRIPT" 
		else
			echo "INFO:$package ya esta instalado." >>"$LOG_EJECUCION_SCRIPT" 
		fi
	done
}

# instalar dynatrace
function instalar_dynatrace() {

	echo "================================================================================"  >>"$LOG_EJECUCION_SCRIPT"
	echo "INFO:Obtencion_keys_installer_dynatrace $APP_CATALYS_MIS_INSTALLER_SHELL"  >>"$LOG_EJECUCION_SCRIPT"
	obtener_secreto ${DYNATRACE_SECRET} ${DYNATRACE_DIR}
		
	# Set your Dynatrace API token and desired host properties
	source ${DYNATRACE_DIR}
	rm -rf ${DYNATRACE_DIR}


	echo "Dynatrace OneAgent Installation and Service Management Script">>"$LOG_EJECUCION_SCRIPT"
	echo "----------------------------------------------------------">>"$LOG_EJECUCION_SCRIPT"

	# Check if Dynatrace OneAgent is already installed
	if [ -d "/opt/dynatrace/oneagent" ]; then
		echo "Dynatrace OneAgent is installed.">>"$LOG_EJECUCION_SCRIPT"

		# Check if Dynatrace OneAgent service is running
		if systemctl is-active --quiet oneagent.service; then
			echo "Dynatrace OneAgent service is running.">>"$LOG_EJECUCION_SCRIPT"
		else
			echo "Dynatrace OneAgent service is not running. Starting...">>"$LOG_EJECUCION_SCRIPT"
			systemctl start oneagent
		fi
	else
		# Dynatrace not installed, proceed with installation
		echo "Dynatrace OneAgent is not installed. Downloading and installing...">>"$LOG_EJECUCION_SCRIPT"

		# Download the OneAgent package
		if wget -O "$ONEAGENT_PACKAGE" "$ONEAGENT_URL" --header="Authorization: Api-Token $ONEAGENT_API_TOKEN"; then
			echo "Downloading Dynatrace root certificate...">>"$LOG_EJECUCION_SCRIPT"
			if wget "${ONEAGENT_URL_PEM}"; then
				echo "Verifying installer signature...">>"$LOG_EJECUCION_SCRIPT"
				if (echo 'Content-Type: multipart/signed; protocol="application/x-pkcs7-signature"; micalg="sha-256"; boundary="--SIGNED-INSTALLER"'; echo; echo; echo '----SIGNED-INSTALLER'; cat "$ONEAGENT_PACKAGE") | openssl cms -verify -CAfile dt-root.cert.pem > /dev/null; then
					echo "Installing Dynatrace OneAgent..." >>"$LOG_EJECUCION_SCRIPT"
					/bin/sh "$ONEAGENT_PACKAGE"  --set-monitoring-mode=fullstack  --set-app-log-content-access=true --set-host-group="$ONEAGENT_HOST_GROUP"  >>"$LOG_EJECUCION_SCRIPT"
					
				else
					echo "Signature verification failed for Dynatrace OneAgent package. Exiting."  >>"$LOG_EJECUCION_SCRIPT"
					log_a_bucket
					exit 1
				fi
			else
				echo "Failed to download Dynatrace root certificate. Exiting."  >>"$LOG_EJECUCION_SCRIPT"
				log_a_bucket
				exit 1
			fi
		else
			echo "Failed to download Dynatrace OneAgent package. Exiting." >>"$LOG_EJECUCION_SCRIPT"
			log_a_bucket
			exit 1
		fi
	fi

	if [ -d "${ONEAGENT_SEGURITY_FILTER_DIR}" ]; then
		cat <<EOF > ${ONEAGENT_SEGURITY_FILTER_CONFIG_FILE}
{
  "@version": "1.0.0",
  "allowed-log-paths-configuration": [
	{
	  "directory-pattern": "/",
	  "file-pattern": "*[-.\\_]log[-.\\_]*",
	  "action": "INCLUDE"
	},
	{
	  "directory-pattern": "/",
	  "file-pattern": "*[-.\\_]log",
	  "action": "INCLUDE"
	},
	{
	  "directory-pattern": "/logs/",
	  "file-pattern": "*",
	  "action": "INCLUDE"
	},
	{
	  "directory-pattern": "/logs/*/",
	  "file-pattern": "*",
	  "action": "INCLUDE"
	},
	{
	  "directory-pattern": "/",
	  "file-pattern": "*.dat",
	  "action": "INCLUDE"
	},
	{
	  "directory-pattern": "^${APPS_CATALYS_DIR}/**/",
	  "file-pattern": "*",
	  "action": "INCLUDE"
	}
  ]
}
EOF
	fi
				
	$ONEAGENT_CMD  --set-host-name=$HOSTNAME --restart-service
	ONEAGENT_HOST_ID=$($ONEAGENT_CMD --get-host-id)
					
	if [ -z "$ONEAGENT_HOST_ID" ]; then
		echo "ERROR: La variable ONEAGENT_HOST_ID no esta definida."
		log_a_bucket
		exit 1
	fi

}

#ejecuta el modo configurado "inicial"
function ejecutar_despliegue_inicial() {

if [ "${APP}" = "catalys-mis-2.2" ]; then

	#***************************************************************************************************
	#***************************************************************************************************
	#INSTALACION MIS
	#***************************************************************************************************
	#***************************************************************************************************

	echo "================================================================================"  >>"$LOG_EJECUCION_SCRIPT"
	echo "INFO:Inicio_instalacion_catalys-MIS"  >>"$LOG_EJECUCION_SCRIPT"  
	
	echo "================================================================================"  >>"$LOG_EJECUCION_SCRIPT"
	echo "INFO:Obtencion_aplicacion ${APP_CATALYS_MIS_INSTALLER_SHELL}"  >>"$LOG_EJECUCION_SCRIPT"  
	descargar_desde_bucket ${APP_CATALYS_MIS_INSTALLER_SHELL}

	echo "================================================================================"  >>"$LOG_EJECUCION_SCRIPT"
	echo "INFO:validacion_archivo_aplicacion ${APP_CATALYS_MIS_INSTALLER_SHELL}"  >>"$LOG_EJECUCION_SCRIPT"
	validar_archivo ${APP_CATALYS_MIS_INSTALLER_SHELL}
	
	echo "================================================================================"  >>"$LOG_EJECUCION_SCRIPT"
	echo "INFO:Obtencion_licencia_aplicacion ${APP_CATALYS_MIS_INSTALLER_SHELL}"  >>"$LOG_EJECUCION_SCRIPT"
	obtener_secreto ${APP_LICENSE_SECRET} ${APPS_LICENSE_FILE_PATH}
	 
	echo "================================================================================"  >>"$LOG_EJECUCION_SCRIPT"
	echo "INFO:Resplado_directorio ${APP_CATALYS_DIR_MIS}"  >>"$LOG_EJECUCION_SCRIPT"
	respaldar ${APP_CATALYS_DIR_MIS} ${BACKUP_FILE_MIS}
	 
	echo "================================================================================"  >>"$LOG_EJECUCION_SCRIPT"
	echo "INFO:Generacion_configuracion_installer ${APP_CATALYS_DIR_MIS}"  >>"$LOG_EJECUCION_SCRIPT"

	cat <<EOL > "$WORK_DIR/${APP_CATALYS_MIS_INSTALLER_CONF}"
# install4j response file for Catalys MIS 2.2
haveLicense\$Boolean=true
licenseFile=${APPS_LICENSE_FILE_PATH}
installEPS\$Boolean=false
startService\$Boolean=false
installService\$Boolean=true
sys.adminRights\$Boolean=true
sys.installationDir=$APP_CATALYS_DIR_MIS
sys.languageId=en
sys.programGroupDisabled\$Boolean=false
sys.symlinkDir=$APPS_CATALYS_SYMLINK_DIR
EOL


	echo "================================================================================"  >>"$LOG_EJECUCION_SCRIPT"
	echo "INFO:Ejecucion_installer $APP_CATALYS_DIR_MIS"  >>"$LOG_EJECUCION_SCRIPT"

	${APPS_CATALYS_SYMLINK_DIR}/mis status  >>"$LOG_EJECUCION_SCRIPT"
	${APPS_CATALYS_SYMLINK_DIR}/mis stop  >>"$LOG_EJECUCION_SCRIPT"

	chmod +x $WORK_DIR/${APP_CATALYS_MIS_INSTALLER_SHELL}
	mkdir -p ${APPS_CATALYS_DIR}
	cp ${APPS_LICENSE_FILE_PATH} ${APPS_CATALYS_DIR}  >>"$LOG_EJECUCION_SCRIPT"
	
	sh $WORK_DIR/${APP_CATALYS_MIS_INSTALLER_SHELL} -q -console -varfile $WORK_DIR/${APP_CATALYS_MIS_INSTALLER_CONF} -overwrite -Dinstall4j.debug=true -Dinstall4j.detailStdout=true -Dinstall4j.logTimestamps=true -Dinstall4j.logToStderr=true -Dinstall4j.keepLog=true

	if [ -d $APP_CATALYS_DIR_MIS ]; then
		#configuracion de logs para dynatrace
		echo "INFO:Dynatrace: Configuracion de custom log source"  >>"$LOG_EJECUCION_SCRIPT"
		api-dynatrace "builtin:logmonitoring.custom-log-source-settings" $ONEAGENT_HOST_ID "catalys-mis-log-source" "${APP_CATALYS_DIR_MIS_LOG}"
		api-dynatrace "builtin:logmonitoring.log-storage-settings" $ONEAGENT_HOST_ID "catalys-mis-log-ingest-rule" "${APP_CATALYS_DIR_MIS_LOG}"
		
		
		#modifica la configuracion del mis para definir el hostname de la VM nodo con las sesiones fix.
		cat <<EOF > ${APP_MIS_CONFIG_DIR_FILE}
lrs.logsReplicationServiceClient/connectionManagerBindAddress = ${APP_CATALYS_HOSTNAME_MIS}
ma/managedHosts=<set><value><host>${APP_CATALYS_HOSTNAME_NODE}</host><jmx-service-url>service:jmx:jmxmp://${APP_CATALYS_HOSTNAME_NODE}:10002</jmx-service-url></value></set>
EOF
		
		#inicio de servicio mis
		${APPS_CATALYS_SYMLINK_DIR}/mis start  >>"$LOG_EJECUCION_SCRIPT"
		
		# Si el mis esta en el puerto 8080 permite el portforwarding para el ssh de un usuario
		# if grep -q "AllowTcpForwarding" /etc/ssh/sshd_config; then
			# # Si existe, reemplaza la linea correspondiente
			 # sed -i "s/^.*AllowTcpForwarding.*\$/AllowTcpForwarding yes/" /etc/ssh/sshd_config
		# else
			# # Si no existe, agrega una nueva linea al final del archivo
			# echo "AllowTcpForwarding yes" |  tee -a /etc/ssh/sshd_config > /dev/null
		# fi
		# sudo systemctl restart sshd

	else
		echo "ERROR: ${APP_CATALYS_DIR_MIS} no existe despues de la instalacion"  >>"$LOG_EJECUCION_SCRIPT"
		log_a_bucket
		exit 1
	fi
	
  
	echo "================================================================================"  >>"$LOG_EJECUCION_SCRIPT"
	echo "INFO:Listando directorios finales"  >>"$LOG_EJECUCION_SCRIPT"
	echo "$WORK_DIR"  >>"$LOG_EJECUCION_SCRIPT"
	ls -ltr $WORK_DIR >>"$LOG_EJECUCION_SCRIPT"
	echo "${APP_CATALYS_DIR_MIS}"  >>"$LOG_EJECUCION_SCRIPT"
	ls -ltr $APP_CATALYS_DIR_MIS >>"$LOG_EJECUCION_SCRIPT"

	echo "${APPS_CATALYS_SYMLINK_DIR}/"  >>"$LOG_EJECUCION_SCRIPT"
	ls -ltr ${APPS_CATALYS_SYMLINK_DIR}/ >>"$LOG_EJECUCION_SCRIPT"
	echo "/etc/init.d/"  >>"$LOG_EJECUCION_SCRIPT"
	ls -ltr /etc/init.d/ >>"$LOG_EJECUCION_SCRIPT"
	echo "/etc/rc"  >>"$LOG_EJECUCION_SCRIPT"
	ls -ltrR /etc/rc* >>"$LOG_EJECUCION_SCRIPT"


	echo "================================================================================"  >>"$LOG_EJECUCION_SCRIPT"
	echo "INFO:Fin Instalacion"  >>"$LOG_EJECUCION_SCRIPT"

	echo "================================================================================" >>"$LOG_EJECUCION_SCRIPT"
	echo "INFO:Generando archivo de vitacora de inicio para consultar"  >>"$LOG_EJECUCION_SCRIPT"
	echo "journalctl  -u  google-startup-scripts.service --no-pager>$WORK_DIR/journal_${AMBIENTE}_${DATEEXEC}.log" 
	journalctl  -u  google-startup-scripts.service --no-pager>$WORK_DIR/journal_${AMBIENTE}_${DATEEXEC}.log
	
	log_a_bucket
	exit

else ##INSTALACION NODE,NODEINSTANCE,LMA


	#***************************************************************************************************
	#***************************************************************************************************
	#INSTALACION NODE
	#***************************************************************************************************
	#***************************************************************************************************
	
	echo "================================================================================"  >>"$LOG_EJECUCION_SCRIPT"
	echo "INFO:Inicio_instalacion_catalys - ${APP_CATALYS_NODE_INSTALLER_PACKAGE}"  >>"$LOG_EJECUCION_SCRIPT"  

	echo "================================================================================"  >>"$LOG_EJECUCION_SCRIPT"
	echo "INFO:Obtencion_aplicacion ${APP_CATALYS_NODE_INSTALLER_PACKAGE}"  >>"$LOG_EJECUCION_SCRIPT"  
	descargar_desde_bucket ${APP_CATALYS_NODE_INSTALLER_PACKAGE}

	echo "================================================================================"  >>"$LOG_EJECUCION_SCRIPT"
	echo "INFO:validacion_archivo_aplicacion ${APP_CATALYS_NODE_INSTALLER_PACKAGE}">>"$LOG_EJECUCION_SCRIPT"
	validar_archivo ${APP_CATALYS_NODE_INSTALLER_PACKAGE}
	
	echo "================================================================================"  >>"$LOG_EJECUCION_SCRIPT"
	echo "INFO:Obtencion_licencia_aplicacion ${APP_CATALYS_NODE_INSTALLER_PACKAGE}"  >>"$LOG_EJECUCION_SCRIPT"
	obtener_secreto ${APP_LICENSE_SECRET} ${APPS_LICENSE_FILE_PATH}
	
	echo "================================================================================"  >>"$LOG_EJECUCION_SCRIPT"
	echo "INFO:Respaldo_directorio ${APP_CATALYS_DIR}"  >>"$LOG_EJECUCION_SCRIPT"
	respaldar ${APP_CATALYS_DIR} ${BACKUP_FILE}
	
	echo "================================================================================"  >>"$LOG_EJECUCION_SCRIPT"
	echo "INFO:Descompresion_directorio ${APP_CATALYS_DIR}"  >>"$LOG_EJECUCION_SCRIPT"

	if unzip -o ${WORK_DIR}/${APP_CATALYS_NODE_INSTALLER_PACKAGE} -d ${APPS_CATALYS_DIR_BASE} >>"$LOG_EJECUCION_SCRIPT" ; then
	  echo "INFO: Directorio de la aplicacion extraido exitosamente." >>"$LOG_EJECUCION_SCRIPT"  
	else
	  echo "ERROR: Fallo al extraer el directorio de la aplicacion." >>"$LOG_EJECUCION_SCRIPT"
	  log_a_bucket
	  exit 1
	fi


	#***************************************************************************************************
	#***************************************************************************************************
	#INSTALACION LMA
	#***************************************************************************************************
	#***************************************************************************************************

	echo "================================================================================"  >>"$LOG_EJECUCION_SCRIPT"
	echo "INFO:Inicio_instalacion_catalys-LMA"  >>"$LOG_EJECUCION_SCRIPT" 

	echo "================================================================================"  >>"$LOG_EJECUCION_SCRIPT"
	echo "INFO:Obtencion_aplicacion ${APP_CATALYS_LMA_INSTALLER_SHELL}"  >>"$LOG_EJECUCION_SCRIPT"  
	descargar_desde_bucket ${APP_CATALYS_LMA_INSTALLER_SHELL}

	echo "================================================================================"  >>"$LOG_EJECUCION_SCRIPT"
	echo "INFO:validacion_archivo_aplicacion ${APP_CATALYS_LMA_INSTALLER_SHELL}"  >>"$LOG_EJECUCION_SCRIPT"
	validar_archivo ${APP_CATALYS_LMA_INSTALLER_SHELL} 
	 
	echo "================================================================================"  >>"$LOG_EJECUCION_SCRIPT"
	echo "INFO:Respaldo_directorio ${APP_CATALYS_DIR_LMA}"  >>"$LOG_EJECUCION_SCRIPT"
	respaldar ${APP_CATALYS_DIR_LMA} ${BACKUP_FILE_LMA}
	 
	echo "================================================================================"  >>"$LOG_EJECUCION_SCRIPT"
	echo "INFO:Generacion_configuracion_installer ${APP_CATALYS_DIR_LMA}"  >>"$LOG_EJECUCION_SCRIPT"

	 cat << EOL > "${WORK_DIR}/${APP_CATALYS_LMA_INSTALLER_CONF}"
# install4j response file for Catalys LMA 2.2
installService\$Boolean=true
startService\$Boolean=false
sys.adminRights\$Boolean=true
sys.installationDir=$APP_CATALYS_DIR_LMA
sys.languageId=en
sys.programGroupDisabled\$Boolean=false
sys.symlinkDir=$APPS_CATALYS_SYMLINK_DIR
EOL


	echo "================================================================================"  >>"$LOG_EJECUCION_SCRIPT"
	echo "INFO:Ejecucion_installer ${APP_CATALYS_DIR_LMA}"  >>"$LOG_EJECUCION_SCRIPT"
	
	${APPS_CATALYS_SYMLINK_DIR}/lma status  >>"$LOG_EJECUCION_SCRIPT"
	${APPS_CATALYS_SYMLINK_DIR}/lma stop  >>"$LOG_EJECUCION_SCRIPT"

	chmod +x ${WORK_DIR}/${APP_CATALYS_LMA_INSTALLER_SHELL}
	sh ${WORK_DIR}/${APP_CATALYS_LMA_INSTALLER_SHELL} -q -console -varfile ${WORK_DIR}/${APP_CATALYS_LMA_INSTALLER_CONF} -overwrite -Dinstall4j.debug=true -Dinstall4j.detailStdout=true -Dinstall4j.logTimestamps=true  -Dinstall4j.logToStderr=true -Dinstall4j.keepLog=true

	
	if [ -d ${APP_CATALYS_DIR_LMA} ]; then
		#configuracion de logs para dynatrace
		echo "INFO:Dynatrace: Configuracion de custom log source"  >>"$LOG_EJECUCION_SCRIPT"
		api-dynatrace "builtin:logmonitoring.custom-log-source-settings" ${ONEAGENT_HOST_ID} "catalys-lma-log-source" "${APP_CATALYS_DIR_LMA_LOG}"
		api-dynatrace "builtin:logmonitoring.log-storage-settings" ${ONEAGENT_HOST_ID} "catalys-lma-log-ingest-rule" "${APP_CATALYS_DIR_LMA_LOG}"
		
		#inicio de servicio dynatrace
		${APPS_CATALYS_SYMLINK_DIR}/lma start  >>"$LOG_EJECUCION_SCRIPT"
	else
		echo "ERROR: ${APP_CATALYS_DIR_LMA} no existe despues de la instalacion"  >>"$LOG_EJECUCION_SCRIPT"
		log_a_bucket
		exit 1
	fi
	

	#***************************************************************************************************
	#***************************************************************************************************
	#INSTALACION NODE INSTANCE
	#***************************************************************************************************
	#***************************************************************************************************
	
	echo "================================================================================"  >>"$LOG_EJECUCION_SCRIPT"
	echo "INFO:Inicio_instalacion_catalys - ${APP_CATALYS_NODE_INSTALLER_INSTANCE_PACKAGE}"  >>"$LOG_EJECUCION_SCRIPT"  

	echo "================================================================================"  >>"$LOG_EJECUCION_SCRIPT"
	echo "INFO:Obtencion_aplicacion ${APP_CATALYS_NODE_INSTALLER_INSTANCE_PACKAGE}"  >>"$LOG_EJECUCION_SCRIPT"  
	descargar_desde_bucket ${APP_CATALYS_NODE_INSTALLER_INSTANCE_PACKAGE}

	echo "================================================================================"  >>"$LOG_EJECUCION_SCRIPT"
	echo "INFO:validacion_archivo_aplicacion ${APP_CATALYS_NODE_INSTALLER_INSTANCE_PACKAGE}"  >>"$LOG_EJECUCION_SCRIPT" 
	validar_archivo ${APP_CATALYS_NODE_INSTALLER_INSTANCE_PACKAGE}

	echo "================================================================================"  >>"$LOG_EJECUCION_SCRIPT"
	echo "INFO:Respaldo_directorio ${APP_CATALYS_DIR_INSTANCE}"  >>"$LOG_EJECUCION_SCRIPT"
	respaldar ${APP_CATALYS_DIR_INSTANCE} ${BACKUP_FILE_NODE_INSTANCE}
	
	echo "================================================================================"  >>"$LOG_EJECUCION_SCRIPT"
	echo "INFO:Ejecucion_installer ${APP_CATALYS_DIR_INSTANCE}"  >>"$LOG_EJECUCION_SCRIPT"
	
	if unzip -o ${WORK_DIR}/${APP_CATALYS_NODE_INSTALLER_INSTANCE_PACKAGE} -d ${APPS_CATALYS_DIR_BASE}	>>"$LOG_EJECUCION_SCRIPT" ; then
	  echo "INFO: Directorio de la aplicacion extraido exitosamente." >>"$LOG_EJECUCION_SCRIPT"
	  
	  #instalacion de licencia en directorio base para uso de la configuracion de sesiones fix
	  cp ${APPS_LICENSE_FILE_PATH} ${APPS_CATALYS_DIR}  >>"$LOG_EJECUCION_SCRIPT"
	    
	  echo "================================================================================"  >>"$LOG_EJECUCION_SCRIPT"
	  echo "INFO:Obtencion_sesiones_autenticacion ${APP_CATALYS_DIR_INSTANCE}"  >>"$LOG_EJECUCION_SCRIPT"
	  obtener_secreto ${APP_NODE_INSTANCE_SESION_CONFIG_SECRET} ${APP_NODE_INSTANCE_SESION_CONFIG_DIR}
	  
	  echo "================================================================================"  >>"$LOG_EJECUCION_SCRIPT"
	  echo "INFO:Obtencion_JKS_Bloomberg ${APP_CATALYS_DIR_INSTANCE}"  >>"$LOG_EJECUCION_SCRIPT"
	  obtener_secreto ${APP_NODE_INSTANCE_SESION_BLOOMBERG_JKS_SECRET} ${APP_NODE_INSTANCE_SESION_BLOOMBERG_JKS_DIR}
	  
	  echo "================================================================================"  >>"$LOG_EJECUCION_SCRIPT"
	  echo "INFO:Obtencion_Keystore_Bloomberg ${APP_CATALYS_DIR_INSTANCE}"  >>"$LOG_EJECUCION_SCRIPT"
	  obtener_secreto ${APP_NODE_INSTANCE_SESION_BLOOMBERG_KEYST_SECRET} ${APP_NODE_INSTANCE_SESION_BLOOMBERG_KEYST_DIR}

	  echo "================================================================================"  >>"$LOG_EJECUCION_SCRIPT"
	  echo "INFO:ejecutando scripts de inicio de sesiones ${APP_CATALYS_DIR_INSTANCE}"  >>"$LOG_EJECUCION_SCRIPT"
	  
	  for script in ${APP_NODE_INSTANCE_SESION_SCRIPTS} ; do
		if [ -f "$script" ]; then
		
		    #crea directorio de logue de sesiones en el caso de que no exista
			mkdir -p "${APP_NODE_INSTANCE_SESION_LOG_DIR}"			
			chmod +x "$script"
			
			echo "INFO: Script de sesion a ejecutar: $script" >>"$LOG_EJECUCION_SCRIPT"	
			
			SCRIPT_NOMBRE=$(basename "$script" .sh)
			nohup "$script" > "${APP_NODE_INSTANCE_SESION_LOG_DIR}/${SCRIPT_NOMBRE}_${DATEEXEC}.log"  2>&1 &
			PIDSCRIPT=$!
			
			echo "INFO: Script de sesion ejecutado en : ${PIDSCRIPT}  : ${APP_NODE_INSTANCE_SESION_LOG_DIR}/${SCRIPT_NOMBRE}_${DATEEXEC}.log " >>"$LOG_EJECUCION_SCRIPT"
		fi
	  done
	  echo "INFO: Scripts de sesiones ejecutados" >>"$LOG_EJECUCION_SCRIPT"
	  	  
	  #configuracion de logs para dynatrace sesiones fix
	  echo "INFO:Dynatrace: Configuracion de custom log source de sesiones fix"  >>"$LOG_EJECUCION_SCRIPT"
	  api-dynatrace "builtin:logmonitoring.custom-log-source-settings" ${ONEAGENT_HOST_ID} "catalys-mainlogs-log-source" "${APP_CATALYS_DIR_INSTANCE_MAIN_LOG}"
	  api-dynatrace "builtin:logmonitoring.log-storage-settings" ${ONEAGENT_HOST_ID} "catalys-mainlogs-log-ingest-rule" "${APP_CATALYS_DIR_INSTANCE_MAIN_LOG}"
	  
	  api-dynatrace "builtin:logmonitoring.custom-log-source-settings" ${ONEAGENT_HOST_ID} "catalys-persistence-log-source" "${APP_CATALYS_DIR_INSTANCE_PERS_LOG}"
	  api-dynatrace "builtin:logmonitoring.log-storage-settings" ${ONEAGENT_HOST_ID} "catalys-persistence-log-ingest-rule" "${APP_CATALYS_DIR_INSTANCE_PERS_LOG}"
	  
	  #api-dynatrace "builtin:logmonitoring.custom-log-source-settings" ${ONEAGENT_HOST_ID} "catalys-hpl-log-source" "${APP_CATALYS_DIR_INSTANCE_HPL_LOG}"
	  #api-dynatrace "builtin:logmonitoring.log-storage-settings" ${ONEAGENT_HOST_ID} "catalys-hpl-log-ingest-rule" "${APP_CATALYS_DIR_INSTANCE_HPL_LOG}"
	  
	  api-dynatrace "builtin:logmonitoring.custom-log-source-settings" ${ONEAGENT_HOST_ID} "catalys-archive-log-source" "${APP_CATALYS_DIR_INSTANCE_ARCHIVE_LOG}"
	  api-dynatrace "builtin:logmonitoring.log-storage-settings" ${ONEAGENT_HOST_ID} "catalys-archive-log-ingest-rule" "${APP_CATALYS_DIR_INSTANCE_ARCHIVE_LOG}"
	  
	else
	  echo "ERROR: Fallo al extraer el directorio de la aplicacion. ${APP_CATALYS_DIR_INSTANCE}" >>"$LOG_EJECUCION_SCRIPT"
	  log_a_bucket
	  exit 1
	fi


	echo "================================================================================"  >>"$LOG_EJECUCION_SCRIPT"
	echo "INFO:Listando directorios finales"  >>"$LOG_EJECUCION_SCRIPT"
	echo "$WORK_DIR"  >>"$LOG_EJECUCION_SCRIPT"
	ls -ltr $WORK_DIR >>"$LOG_EJECUCION_SCRIPT"
	echo "${APP_CATALYS_DIR}"  >>"$LOG_EJECUCION_SCRIPT"
	ls -ltr $APP_CATALYS_DIR >>"$LOG_EJECUCION_SCRIPT"
	echo "${APP_CATALYS_DIR_INSTANCE}"  >>"$LOG_EJECUCION_SCRIPT"
	ls -ltrR $APP_CATALYS_DIR_INSTANCE >>"$LOG_EJECUCION_SCRIPT"
	echo "${APP_CATALYS_DIR_LMA}"  >>"$LOG_EJECUCION_SCRIPT"
	ls -ltr $APP_CATALYS_DIR_LMA >>"$LOG_EJECUCION_SCRIPT"

	echo "$APPS_CATALYS_SYMLINK_DIR/"  >>"$LOG_EJECUCION_SCRIPT"
	ls -ltr $APPS_CATALYS_SYMLINK_DIR/ >>"$LOG_EJECUCION_SCRIPT"
	echo "/etc/init.d/"  >>"$LOG_EJECUCION_SCRIPT"
	ls -ltr /etc/init.d/ >>"$LOG_EJECUCION_SCRIPT"
	echo "/etc/rc"  >>"$LOG_EJECUCION_SCRIPT"
	ls -ltrR /etc/rc* >>"$LOG_EJECUCION_SCRIPT"


	echo "================================================================================"  >>"$LOG_EJECUCION_SCRIPT"
	echo "INFO:Fin Instalacion"  >>"$LOG_EJECUCION_SCRIPT"

	echo "================================================================================" >>"$LOG_EJECUCION_SCRIPT"
	echo "INFO:Generando archivo de vitacora de inicio para consultar"  >>"$LOG_EJECUCION_SCRIPT"
	echo "journalctl  -u  google-startup-scripts.service --no-pager>$WORK_DIR/journal_${AMBIENTE}_${DATEEXEC}.log" 
	journalctl  -u  google-startup-scripts.service --no-pager>$WORK_DIR/journal_${AMBIENTE}_${DATEEXEC}.log
	
fi

}
#fin ejecutar_despliegue_inicial



#***************************************************************************************************
#***************************************************************************************************
#INSTALACION PAQUETES
#***************************************************************************************************
#***************************************************************************************************

echo "================================================================================"  >>"$LOG_EJECUCION_SCRIPT"
echo "INFO:Inicio"  >>"$LOG_EJECUCION_SCRIPT"  
instalar_paquetes


#***************************************************************************************************
#***************************************************************************************************
#INSTALACION MONITOREO
#***************************************************************************************************
#***************************************************************************************************

echo "================================================================================"  >>"$LOG_EJECUCION_SCRIPT"
echo "INFO:Instalacion Dynatrace OneAgent"  >>"$LOG_EJECUCION_SCRIPT"
instalar_dynatrace

#***************************************************************************************************
#***************************************************************************************************
#CONFIGURACION DE MODO DE DESPLIEGUE
#***************************************************************************************************
#***************************************************************************************************

# Descargar configuracion para script de inicio
descargar_desde_bucket ${CONFIG_FILE_EJECUCION_SCRIPT}
source "$WORK_DIR/${CONFIG_FILE_EJECUCION_SCRIPT}"

# Leer estado actual del lock
if [ -f "$LOCK_FILE_EJECUCION_SCRIPT" ]; then
    source "$LOCK_FILE_EJECUCION_SCRIPT"
else
    last_action="ninguna"
    last_mode="ninguna"
    last_version="ninguna"
    timestamp="ninguna"
fi

# Determinar accion y estado a registrar
read accion_final modo_final version_final <<< $(definir_modo_y_estado "$mode" "$version" "$last_action" "$last_version" "$last_mode")


#***************************************************************************************************
#***************************************************************************************************
#EJECUCION DE DESPLIEGUE
#***************************************************************************************************
#***************************************************************************************************

# Ejecutar accion segun el modo
if [[ "$accion_final" == "skip" ]]; then
    echo "No se realizara ninguna accion para el modo $mode." | tee -a "$LOG_EJECUCION_SCRIPT"
else
    case $modo_final in
        "inicial"|"inicial-forzado")
            ejecutar_despliegue_inicial
            ;;
        "update")
            #ejecutar_actualizacion
            ;;
        *)
            echo "Modo desconocido: $modo_final. No se realizara ninguna accion." | tee -a "$LOG_EJECUCION_SCRIPT"
            ;;
    esac
fi

#El el directorio root mueve los logs de ejecucion antiguos dejando solo los de esta ejecucion.
mover_logs_antiguos

# Registrar el estado final
registrar_estado "$accion_final" "$modo_final" "$version_final"
log_a_bucket
