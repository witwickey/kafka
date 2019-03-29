FROM alpine:3.8

## Install Kafka+Zookeeper, theirs deps and custom nc-less busybox
RUN apk add tar &&\
    apk --no-cache add bash curl openjdk8-jre-base &&\
	curl -O https://fastscore.ai/alpine/v3.8/busybox-1.28.4-r1.apk &&\
	apk --no-cache --allow-untrusted add busybox-1.28.4-r1.apk &&\
	rm busybox-1.28.4-r1.apk &&\
	curl -L https://archive.apache.org/dist/kafka/2.1.0/kafka_2.12-2.1.0.tgz | tar zxf - &&\
	mv kafka_2.12-2.1.0 /kafka &&\
	rm -rf /kafka/site-docs /kafka/bin/windows &&\
	chmod -R g=u /kafka

ENV PATH=/kafka/bin:${PATH}

EXPOSE 2181 2888 3888 9092

# The entry.sh script needs to modify server.properties.
# Instead, we move server.properties to server.properties.original,
# and then we setup server.properties as a symbolic link to /tmp/server.properties.
# The entry.sh script copies server.properties.original into /tmp, where it can be modified

RUN mv /kafka/config/server.properties /kafka/config/server.properties.original && \
      ln -s /tmp/server.properties /kafka/config/server.properties

COPY entry.sh /
ENTRYPOINT ["/entry.sh"]
