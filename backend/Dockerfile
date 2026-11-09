# syntax=docker/dockerfile:1

FROM mcr.microsoft.com/dotnet/sdk:10.0 AS build
WORKDIR /src
COPY src/TimeFix.Server/TimeFix.Server.csproj src/TimeFix.Server/
RUN dotnet restore src/TimeFix.Server/TimeFix.Server.csproj
COPY src/ src/
RUN dotnet publish src/TimeFix.Server/TimeFix.Server.csproj -c Release -o /app --no-restore

FROM mcr.microsoft.com/dotnet/aspnet:10.0 AS runtime
WORKDIR /app
COPY --from=build /app .

# SQLite data lives in /data (mount a volume there).
RUN mkdir -p /data && chown -R $APP_UID /data
VOLUME ["/data"]

ENV ASPNETCORE_HTTP_PORTS=8080 \
    Database__Provider=Sqlite \
    Database__ConnectionString="Data Source=/data/timefix.db"

EXPOSE 8080
USER $APP_UID

HEALTHCHECK --interval=30s --timeout=5s --start-period=20s --retries=3 \
    CMD ["dotnet", "TimeFix.Server.dll", "healthcheck"]

ENTRYPOINT ["dotnet", "TimeFix.Server.dll"]
