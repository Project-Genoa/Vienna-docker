FROM alpine:3.19.1 AS java
WORKDIR /java
RUN wget -O - https://github.com/adoptium/temurin17-binaries/releases/download/jdk-17.0.11%2B9/OpenJDK17U-jdk_x64_alpine-linux_hotspot_17.0.11_9.tar.gz | gunzip | tar -x --strip-components=1
ENV PATH=/java/bin:$PATH

FROM ubuntu:24.04 AS java-build
RUN apt-get update; apt-get install -y wget
WORKDIR /java-17
RUN wget -O - https://github.com/adoptium/temurin17-binaries/releases/download/jdk-17.0.11%2B9/OpenJDK17U-jdk_x64_linux_hotspot_17.0.11_9.tar.gz | gunzip | tar -x --strip-components=1
WORKDIR /java-8
RUN wget -O - https://github.com/adoptium/temurin8-binaries/releases/download/jdk8u412-b08/OpenJDK8U-jdk_x64_linux_hotspot_8u412b08.tar.gz | gunzip | tar -x --strip-components=1

FROM java-build AS build
WORKDIR /fountain
RUN mkdir Fountain-bridge; wget -O - https://github.com/Project-Genoa/Fountain-bridge/archive/3d4eb8c0d54ba797dfaa85afd0879a93d4c07218.tar.gz | gunzip | tar -C Fountain-bridge -x --strip-components=1
RUN mkdir Fountain-fabric; wget -O - https://github.com/Project-Genoa/Fountain-fabric/archive/5b68ee996742791987bbd734117bbef4ad41bd47.tar.gz | gunzip | tar -C Fountain-fabric -x --strip-components=1
RUN mkdir Fountain-connector-plugin-base; wget -O - https://github.com/Project-Genoa/Fountain-connector-plugin-base/archive/ddb780d03e61785cc1e1cb9e920e7e5bf14a3ff7.tar.gz | gunzip | tar -C Fountain-connector-plugin-base -x --strip-components=1
RUN mkdir Protocol; wget -O - https://github.com/Project-Genoa/Protocol/archive/b5b4225de434115c4098b13df7419bf2db61319f.tar.gz | gunzip | tar -C Protocol -x --strip-components=1
WORKDIR /vienna
RUN mkdir Vienna; wget -O - https://github.com/Project-Genoa/Vienna/archive/ada65564a1071386bd18140e57e05f2ab97c4fbd.tar.gz | gunzip | tar -C Vienna -x --strip-components=1
RUN mkdir Vienna-fabric; wget -O - https://github.com/Project-Genoa/Vienna-fabric/archive/7ecefce63402a7a6d5ddc0448e8bd4e98dc060c8.tar.gz | gunzip | tar -C Vienna-fabric -x --strip-components=1
WORKDIR /fountain/Protocol
RUN PATH=/java-8/bin:$PATH ./gradlew publishToMavenLocal
WORKDIR /fountain/Fountain-connector-plugin-base
RUN PATH=/java-17/bin:$PATH ./mvnw install
WORKDIR /fountain/Fountain-bridge
RUN PATH=/java-17/bin:$PATH ./mvnw package
WORKDIR /fountain/Fountain-fabric
RUN PATH=/java-17/bin:$PATH ./gradlew build
RUN PATH=/java-17/bin:$PATH ./gradlew publishToMavenLocal
WORKDIR /vienna/Vienna
RUN PATH=/java-17/bin:$PATH ./mvnw package
RUN PATH=/java-17/bin:$PATH ./mvnw install
WORKDIR /vienna/Vienna-fabric
RUN PATH=/java-17/bin:$PATH ./gradlew build

FROM java AS fountain-bridge
COPY --from=build /fountain/Fountain-bridge/target/fountain-0.0.1-SNAPSHOT-jar-with-dependencies.jar /fountain/
WORKDIR /fountain
ENTRYPOINT ["/java/bin/java", "-jar", "fountain-0.0.1-SNAPSHOT-jar-with-dependencies.jar"]
EXPOSE 19132/udp

FROM java AS fountain-fabric
RUN mkdir /fabric; mkdir /fabric/mods
RUN wget -O /fabric/fabric-server-mc.1.20.4-loader.0.15.10-launcher.1.0.1.jar https://meta.fabricmc.net/v2/versions/loader/1.20.4/0.15.10/1.0.1/server/jar
RUN wget -O /fabric/mods/fabric-api-0.97.0+1.20.4.jar https://mediafilez.forgecdn.net/files/5253/510/fabric-api-0.97.0%2B1.20.4.jar
COPY --from=build /fountain/Fountain-fabric/build/libs/fountain-0.0.1.jar /fabric/mods/
WORKDIR /fabric
RUN java -jar fabric-server-mc.1.20.4-loader.0.15.10-launcher.1.0.1.jar -nogui
RUN rm -r server.properties eula.txt logs; echo 'eula=true' > eula.txt; mkdir world; echo -e 'online-mode=false\nenforce-secure-profile=false\nsync-chunk-writes=false\nspawn-protection=0\ngamemode=creative' > world/server.properties; ln -s world/server.properties ./
ENTRYPOINT ["/java/bin/java", "-jar", "fabric-server-mc.1.20.4-loader.0.15.10-launcher.1.0.1.jar"]
CMD ["-nogui"]
EXPOSE 25565/tcp
VOLUME /fabric/world

FROM java AS vienna-eventbus
COPY --from=build /vienna/Vienna/eventbus/server/target/eventbus-server-0.0.1-SNAPSHOT-jar-with-dependencies.jar /vienna/
WORKDIR /vienna
ENTRYPOINT ["/java/bin/java", "-jar", "eventbus-server-0.0.1-SNAPSHOT-jar-with-dependencies.jar"]
EXPOSE 5532/tcp

FROM java AS vienna-objectstore
COPY --from=build /vienna/Vienna/objectstore/server/target/objectstore-server-0.0.1-SNAPSHOT-jar-with-dependencies.jar /vienna/
WORKDIR /vienna
ENTRYPOINT ["/java/bin/java", "-jar", "objectstore-server-0.0.1-SNAPSHOT-jar-with-dependencies.jar", "-dataDir", "/data"]
EXPOSE 5396/tcp
VOLUME /data

FROM java AS vienna-apiserver
COPY --from=build /vienna/Vienna/apiserver/target/apiserver-0.0.1-SNAPSHOT-jar-with-dependencies.jar /vienna/
WORKDIR /vienna
ENTRYPOINT ["/java/bin/java", "-jar", "apiserver-0.0.1-SNAPSHOT-jar-with-dependencies.jar", "-db", "/data/earth.db", "-staticData", "/static"]
EXPOSE 8080/tcp
VOLUME /data
VOLUME /static

FROM java AS vienna-utils-locator
COPY --from=build /vienna/Vienna/utils/locator/target/utils-locator-0.0.1-SNAPSHOT-jar-with-dependencies.jar /vienna/
WORKDIR /vienna
ENTRYPOINT ["/java/bin/java", "-jar", "utils-locator-0.0.1-SNAPSHOT-jar-with-dependencies.jar"]
EXPOSE 8080/tcp

FROM java AS vienna-utils-cdn
COPY --from=build /vienna/Vienna/utils/cdn/target/utils-cdn-0.0.1-SNAPSHOT-jar-with-dependencies.jar /vienna/
WORKDIR /vienna
ENTRYPOINT ["/java/bin/java", "-jar", "utils-cdn-0.0.1-SNAPSHOT-jar-with-dependencies.jar", "-resourcePackFile", "/data/resourcepack"]
EXPOSE 8080/tcp
VOLUME /data

FROM java AS vienna-buildplate-launcher
COPY --from=build /vienna/Vienna/buildplate/launcher/target/buildplate-launcher-0.0.1-SNAPSHOT-jar-with-dependencies.jar /vienna/
COPY --from=build /vienna/Vienna/buildplate/connector-plugin/target/buildplate-connector-plugin-0.0.1-SNAPSHOT-jar-with-dependencies.jar /vienna/
COPY --from=fountain-bridge /fountain /fountain
COPY --from=fountain-fabric /fabric /fabric
COPY --from=build /vienna/Vienna-fabric/build/libs/vienna-0.0.1.jar /fabric/mods/
WORKDIR /vienna
ENTRYPOINT ["/java/bin/java", "-jar", "buildplate-launcher-0.0.1-SNAPSHOT-jar-with-dependencies.jar", "-bridgeJar", "/fountain/fountain-0.0.1-SNAPSHOT-jar-with-dependencies.jar", "-serverTemplateDir", "/fabric", "-fabricJarName", "fabric-server-mc.1.20.4-loader.0.15.10-launcher.1.0.1.jar", "-connectorPluginJar", "/vienna/buildplate-connector-plugin-0.0.1-SNAPSHOT-jar-with-dependencies.jar"]
EXPOSE 19132-19141/udp

FROM java AS vienna-tappablesgenerator
COPY --from=build /vienna/Vienna/tappablesgenerator/target/tappablesgenerator-0.0.1-SNAPSHOT-jar-with-dependencies.jar /vienna/
WORKDIR /vienna
ENTRYPOINT ["/java/bin/java", "-jar", "tappablesgenerator-0.0.1-SNAPSHOT-jar-with-dependencies.jar", "-staticData", "/static"]
VOLUME /static

FROM java AS vienna-utils-tools-buildplate-importer
COPY --from=build /vienna/Vienna/utils/tools/buildplate-importer/target/utils-tools-buildplate-importer-0.0.1-SNAPSHOT-jar-with-dependencies.jar /vienna/
WORKDIR /vienna
ENTRYPOINT ["/java/bin/java", "-jar", "utils-tools-buildplate-importer-0.0.1-SNAPSHOT-jar-with-dependencies.jar", "-db", "/data/earth.db"]
VOLUME /data
