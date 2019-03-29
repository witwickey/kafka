#!/usr/bin/env sh
set -e

## Parse args
PORT=9092
LISTENER=kafka
for i in $@; do case $i in
	-port=*) PORT="${i#-port=}"; ;;
	-listener=*) LISTENER="${i#-listener=}"; ;;
	-principal=*) PRINCIPAL="${i#-principal=}"; ;;
	-keytab=*) KEYTAB="${i#-keytab=}"; ;;
	-kdc=*) KDC="${i#-kdc=}"; ;;
	-silent) SILENT=1; ;;
esac; done

## Generate configs
cp /kafka/config/server.properties.original /tmp/server.properties
KAFKA_PROPS=/tmp/server.properties
echo >> $KAFKA_PROPS
## SASL_PLAINTEXT security
if [ "$PRINCIPAL" ] && [ "$KEYTAB" ] && [ "$KDC" ]; then
	## Extract realm and name form PRINCIPAL
	PRINCIPAL_REALM=${PRINCIPAL#*@}
	PRINCIPAL_NAME=${PRINCIPAL%/*}
	## Inject path to JAAS into KAFKA_OPTS
	KAFKA_JAAS=/kafka/config/kafka.jaas
	sed -i '16iKAFKA_OPTS="-Djava.security.auth.login.config=/kafka/config/kafka.jaas"' /kafka/bin/kafka-run-class.sh
	## Generate JAAS
	cat >$KAFKA_JAAS <<EOF
KafkaServer {
  com.sun.security.auth.module.Krb5LoginModule required
  useKeyTab=true
  storeKey=true
  useTicketCache=true
  keyTab="$KEYTAB"
  principal="$PRINCIPAL";
};
KafkaClient {
  com.sun.security.auth.module.Krb5LoginModule required
  useKeyTab=true
  keyTab="$KEYTAB"
  principal="$PRINCIPAL";
};
EOF
	## Generate krb5.conf
	cat >/etc/krb5.conf <<EOF
[libdefaults]
default_realm = $PRINCIPAL_REALM
rdns = false
[realms]
$PRINCIPAL_REALM = {
  kdc = $KDC
  rdns = false
}
[domain_realm]
realm = $PRINCIPAL_REALM
[logging]
kdc = CONSOLE
EOF
	## Kafka server
	cat >>$KAFKA_PROPS <<EOF
listeners=SASL_PLAINTEXT://:$PORT
advertised.listeners=SASL_PLAINTEXT://$LISTENER:$PORT
inter.broker.listener.name=SASL_PLAINTEXT
sasl.kerberos.service.name=$PRINCIPAL_NAME
allow.everyone.if.no.acl.found=true
controlled.shutdown.enable=false
EOF
## PLAINTEXT security
else
	cat >>$KAFKA_PROPS <<EOF
listeners=PLAINTEXT://:$PORT
advertised.listeners=PLAINTEXT://$LISTENER:$PORT
controlled.shutdown.enable=false
EOF
fi

## Decrease verbosity
if [ "$SILENT" ]; then
	cat >>/kafka/config/log4j.properties <<EOF
log4j.rootLogger=WARN, stdout
log4j.logger.kafka=WARN
log4j.logger.org.apache.kafka=WARN
log4j.logger.org.apache.zookeeper=WARN
log4j.logger.org.I0Itec.zkclient.ZkClient=WARN
EOF
fi

## Start Zookepeer
zookeeper-server-start.sh -daemon /kafka/config/zookeeper.properties

## Start Kafka
exec kafka-server-start.sh $KAFKA_PROPS
