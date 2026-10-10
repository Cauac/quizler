FROM clojure:temurin-21-tools-deps AS build
WORKDIR /app
COPY deps.edn ./
RUN clojure -P && clojure -P -T:build
COPY build.clj ./
COPY src ./src
RUN clojure -T:build uberjar

FROM eclipse-temurin:21-jre
RUN useradd --system --uid 10001 --no-create-home quizler
WORKDIR /app
COPY --from=build /app/target/quizler-server.jar ./quizler-server.jar
USER 10001
EXPOSE 8080
ENTRYPOINT ["java", "-XX:MaxRAMPercentage=75", "-jar", "quizler-server.jar"]
