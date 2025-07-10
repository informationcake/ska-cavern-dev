# Ska-Cavern Development Environment

This README outlines the setup and troubleshooting steps for the Ska-Cavern development environment, which includes services like Cavern (VOSpace implementation), PosixMapper (for POSIX user/group mapping), HAProxy (SSL termination), Nginx proxies, RabbitMQ, and PostgreSQL databases.

## 0. Prerequisites / Dependencies

This project relies on additional external repositories for its build contexts. Please ensure you have cloned the following repositories/directories into your home directory (`${HOME}`) before building and running the Docker Compose environment:

* **`ska-src-dm-local-data-preparer`**: [This repository](https://gitlab.com/ska-telescope/src/src-dm/ska-src-dm-local-data-preparer) is the source for the `core` application and `celery-worker`. Ensure it is cloned into `~/ska-src-dm-local-data-preparer`.
* **`cavern-code/vos/cavern`**: This directory within a [`cavern-code` repository](https://github.com/opencadc/vos/tree/main/cavern) is the build context for the `cavern` service. Ensure you clone `cavern-code` and that the `vos/cavern` path exists within it (e.g., `~/cavern-code/vos/cavern`).

Update the gradle version (unsure why this is needed, perhaps a more recent push to VOS-Cavern isn't updated yet)
In the build.gradle file, update the line:
```implementation 'org.opencadc:cadc-vos-server:[2.0.20,)'```
to:
```implementation 'org.opencadc:cadc-vos-server:2.0.19'```

## 1. Services Overview

The `docker-compose.yml` orchestrates the following key services, outlining their roles and how they interact:

* **`core`**: This is the main data preparer application (exposed on host port `8000`). It's responsible for orchestrating data preparation jobs, which often involve interacting with `cavern` to manage VOSpace files.
* **`celery-worker`**: These are background workers that pick up tasks from `rabbitmq`. They are responsible for executing the actual data operations, such as creating user directories within VOSpace.
* **`rabbitmq`**: Acts as a message broker for `celery-worker` tasks, facilitating asynchronous communication between `core` and its workers.
* **`postgres_cavern`**: A PostgreSQL instance dedicated to storing data for Cavern's Universal Worker Service (UWS), which manages asynchronous jobs within Cavern itself. It initializes with a `uws` schema.
* **`postgres_posixmapper`**: Another PostgreSQL instance used by the `posixmapper` service for storing POSIX mapping data. It initializes with a `mapping` schema.
* **`haproxy`**: Serves as the central entry point for external HTTPS traffic to `cavern` and `posixmapper-proxy`. It performs SSL termination (listening on host port `8443` and forwarding to internal port `443` HTTPS) and acts as a reverse proxy, routing requests based on URL paths.
* **`posixmapper-proxy`**: An Nginx instance specifically configured to proxy requests to the `posixmapper` service. It's crucial for re-writing HTTPS requests to HTTP internally for `posixmapper` and serves static capabilities XML files related to POSIX mapping.
* **`posixmapper`**: This service handles POSIX user and group ID mapping. It queries `postgres_posixmapper` for mapping information and is a dependency for services like `cavern` that need to resolve user identities to POSIX IDs.
* **`cavern`**: The core VOSpace service. It provides VOSpace functionality, including node management and data transfers. It relies on `postgres_cavern` for its UWS database and interacts with `posixmapper` (via `posixmapper-proxy`) for user identity resolution.
* **`registrymock`**: An Nginx instance acting as a mock IVOA Registry service. It serves predefined `resource-caps.xml` and handles OpenID Connect (OIDC) endpoints, providing static `.json` files for OIDC discovery, user information, and JWKS.

## Troubleshooting Progress & Current Blocking Issue

This section summarizes the recent troubleshooting efforts to get Cavern fully operational, detailing the progression of issues and our current blocking problem.

### 1. Initial Problem: XML Schema Validation Failure (`cvc-elt.1.a`)

* **Symptom:** When attempting to create a VOSpace `ContainerNode` via `PUT` request, Cavern returned `XML failed schema validation: Error on line 1: cvc-elt.1.a: Cannot find the declaration of element 'vos:ContainerNode'`. This indicated Cavern's internal XML parser couldn't locate/recognize `ContainerNode` in its schema.
* **Resolution:** We switched the `cavern` service in `docker-compose.yml` to use the **official pre-built Docker image (`images.opencadc.org/platform/cavern:0.8.2`)**. This resolved the schema validation error and also fixed issues with the Swagger UI not rendering (due to missing static assets in the local build).

### 2. Intermediary Problem: `posixmapper` Deployment Failure (leading to Cavern 503)

* **Symptom:** After the `cavern` image switch, Cavern failed to initialize, resulting in a `503 Service Unavailable` from HAProxy. Cavern's logs showed it couldn't obtain service URLs from `posixmapper-proxy`.
* **Diagnosis:** We discovered the `posixmapper` container's startup script (`/usr/bin/cadc-tomcat-start`) was failing to unpack its `posix-mapper.war` due to the `unzip` command being missing and a "disk space" error during `unzip` installation within the container. This left `posixmapper` undeployed.
* **Resolution:** We bypassed the problematic `cadc-tomcat-start` script. We extracted `posix-mapper.war` from the official image locally, unpacked it, and then mounted the *unpacked* directory (`~/posixmapper_unpacked`) directly into the `posixmapper` container's Tomcat `webapps` folder (`/usr/share/tomcat/webapps/posix-mapper`) via `docker-compose.yml`. This allowed `posixmapper` to deploy cleanly and start successfully.

### 3. Current Blocking Issue: Persistent Cavern Initialization Failure (`StringIndexOutOfBoundsException`)

* **Symptom:** Despite `posixmapper` now deploying correctly, Cavern still fails to initialize, showing `HTTP Status 500` and the following in its logs:

    ```java
    Caused by: java.lang.RuntimeException: failed to load properties from cache, src=http://posixmapper-proxy:8080/posix-mapper/resource-caps
        at ca.nrc.cadc.reg.client.RegistryClient.getAccessURL(RegistryClient.java:245)
        ...
    Caused by: java.lang.StringIndexOutOfBoundsException: begin 0, end -1, length 21
        at ca.nrc.cadc.util.MultiValuedProperties.load(MultiValuedProperties.java:170)
    ```
* **Detailed Diagnosis:**
    * Cavern's configuration (`cavern.properties`, `cadc-registry.properties`) has been updated to point `org.opencadc.cavern.registryUrl`, `org.opencadc.cavern.posixMapperResourceId`, and `org.opencadc.auth.StandardIdentityManager.capabilitiesURL` to `http://posixmapper-proxy:8080/posix-mapper/capabilities` (the XML capabilities endpoint).
    * We've confirmed via `curl` *from inside the `posixmapper-proxy` container*:
        * `curl http://posixmapper:8080/posix-mapper/capabilities` returns `200 OK` with the expected **XML content**.
        * `curl http://localhost:8080/posix-mapper/resource-caps` returns `200 OK` with `Content-Type: text/plain` and the content of a simple, valid `dummy.key=dummy.value` properties file (which we explicitly served via Nginx at that path).
    * **The Contradiction:** Despite `posixmapper-proxy` serving a `200 OK` with valid properties content at `http://posixmapper-proxy:8080/posix-mapper/resource-caps`, Cavern's `RegistryClient` (specifically `MultiValuedProperties.load`) is *still* attempting to parse it as properties and failing with `StringIndexOutOfBoundsException`. It appears to ignore the `Content-Type` header or has a hardcoded expectation for properties at that exact path. We also tried serving dummy XML at this path, but the error persisted, indicating it's always trying to parse it as properties.

**Current Block:**

The `StandardIdentityManager` (and by extension, Cavern) cannot initialize because it appears to be hardcoded to fetch and parse a properties file from `http://posixmapper-proxy:8080/posix-mapper/resource-caps`, and it fails to parse even a simple `key=value` file, leading to a `StringIndexOutOfBoundsException`. This prevents the entire Cavern service from starting up.

**Questions for the Team:**

* Is there a known issue with `ca.nrc.cadc.util.MultiValuedProperties.load` or `ca.nrc.cadc.reg.client.RegistryClient` in `cavern:0.8.2` (or its underlying `cadc-util` library) that causes it to *insist* on parsing a properties file from `resource-caps` and fail even on valid input?
* Is there a specific, expected content/format for `http://posixmapper-proxy:8080/posix-mapper/resource-caps` that `StandardIdentityManager` requires to successfully initialize? (e.g., specific keys/values, or perhaps it expects XML but is calling a properties parser?)
* Are there any other configuration properties in Cavern that could influence this specific `resource-caps` lookup?
* Could this be related to a specific version of Java or a library incompatibility within the `cavern:0.8.2` image?

Any insights into this particular `MultiValuedProperties.load` behavior or `StandardIdentityManager`'s initialization would be greatly appreciated, as we've exhausted external configuration and file content variations.

## 4. `curl` Commands for Verification and Operations

You will need a valid Bearer token for authenticated requests.

### 4.1. Check Cavern Capabilities

Verifies that the Cavern VOSpace capabilities are accessible. This should return an XML document describing the service's features.

    curl -k https://localhost:8443/cavern/capabilities

### 4.2. Submit Latest Job to Data Preparer (Core Service) and Attempt to Create a VOSpace Node (Reproduces Latest Error)

This section provides the `curl` commands to submit a data preparation job and the command that currently reproduces the VOSpace node creation error.

    curl -X POST \
      -H 'Content-Type: application/json' \
      -H 'Authorization: Bearer eyJ0eXAiOiJKV1QiLCJhbGciOiJIUzI1NiJ9.eyJwcmVmZXJyZWRfdXNlcm5hbWUiOiJ0ZXN0dXNlciIsInN1YiI6ImxvY2FsdGVzdHVzZXJfaWQiLCJpYXQiOjE3NTAyOTU2OTAsImV4cCI6MTc1MDI5OTI5MH0.4lBmhoazmEiUjJRvWxdZTkEYKHUsQKVp9CtPZ-crz0Y' \
      -d '[
            ["testing:prepare_data_test.txt", "testing/84/1c/prepare_data_test.txt", "./testing"]
          ]' \
      http://localhost:8000/

    curl -k -X PUT \
      -H 'Content-Type: application/xml' \
      -H 'Authorization: Bearer eyJ0eXAiOiJKV1QiLCJhbGciOiJIUzI1NiJ9.eyJwcmVmZXJyZWRfdXNlcm5hbWUiOiJ0ZXN0dXNlciIsInN1YiI6ImxvY2FsdGVzdHVzZXJfaWQiLCJpYXQiOjE3NTAyOTU2OTAsImV4cCI6MTc1MDI5OTI5MH0.4lBmhoazmEiUjJRvWxdZTkEYKHUsQKVp9CtPZ-crz0Y' \
      -d '<vos:ContainerNode xmlns:vos="http://www.ivoa.net/xml/VOSpace/v2.0">
            <uri>vos://localhost~cavern_test_instance/home/testuser</uri>
            <properties>
                <property uri="ivo://ivoa.net/vospace/core#owner">testuser</property>
                <property uri="ivo://ivoa.net/vospace/core#group">testgroup</property>
            </properties>
          </vos:ContainerNode>' \
      https://localhost:8443/cavern/nodes/home/testuser
