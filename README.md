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

## 2. Steps Taken to Get Services Working

This section details the step-by-step troubleshooting process undertaken to get the various services in the Ska-Cavern environment to a functional state.

### 2.1. PosixMapper Database Connectivity Issues (Primary Blocker)

* **Problem:** Upon initial review of `docker compose logs posixmapper`, the service failed to start its database connection pool due to `java.lang.NumberFormatException: For input string: "${org.opencadc.posix.mapper.maxActive}"` and a critical `cp: cannot stat '/tmp/config/context.xml': No such file or directory` error.
* **Diagnosis:** This indicated that placeholders in `posixmapper`'s Tomcat `context.xml` were not being resolved. The `cp` error suggested that the intended `context.xml` file, which defines these properties, was not being successfully copied into the container's application directory during startup, leaving the default, unconfigured `context.xml` from the WAR file in use.
* **Resolution Step 1: Direct `context.xml` Mount:** The `docker-compose.yml` was modified to directly mount the host's `config/posixmapper/META-INF/context.xml` to the final unpacked location within the container: `- ./config/posixmapper/META-INF/context.xml:/usr/share/tomcat/webapps/posix-mapper/META-INF/context.xml:ro`. The resulting "Device or resource busy" message during WAR unpacking confirmed this mount was active.
* **Resolution Step 2: Hardcode Database URL:** Despite the direct mount, `posixmapper` still failed with `java.sql.SQLException: Driver:... returned null for URL:${system.POSIX_MAPPER_URL}`. To bypass this property substitution issue, the `url` attribute in `config/posixmapper/META-INF/context.xml` was hardcoded to `jdbc:postgresql://postgres_posixmapper:5432/mapping`.
* **Resolution Step 3: Hardcode Username and Password:** Following the URL fix, `posixmapper` reported `FATAL: password authentication failed for user "${system.POSIX_MAPPER_USERNAME}"`. Similarly, the `username` and `password` attributes in `config/posixmapper/META-INF/context.xml` were hardcoded to `posixmapper` and `posixmapperpwd` respectively.

**Outcome of PosixMapper Fixes:** `posixmapper` successfully connected to its database, completed initialization, and became fully functional.

### 2.3. Cavern Service Initialization & VOSpace NodeNotFound Error

* **Cavern Startup:** Throughout the troubleshooting, `cavern` consistently reported successful startup of its Tomcat application, successful certificate import via `cavern_init_cert.sh`, and correct initialization of its UWS database.
* **User Mapping Observation:** Once `posixmapper` was stable, `cavern` successfully communicated with it for user mapping. For example, during a request for `/home/testuser`, `cavern` logs showed successful resolution of `PosixPrincipal [uidNumber=10000,10000,testuser]`, indicating successful integration.
* **Initial VOSpace Problem:** Initial attempts to `GET` VOSpace nodes (e.g., `/home/testuser`) resulted in a `ca.nrc.cadc.net.ResourceNotFoundException: NodeNotFound: vos://localhost~cavern_test_instance/home/testuser` error. This `NodeNotFound` error was expected, as the VOSpace path did not yet exist in Cavern's underlying data storage (`./data/cavern_files`). This confirmed core services were communicating.
* **Solution Attempt (leading to current issue):** An attempt to create the `ContainerNode` via a `PUT` request with an XML payload was made. This led directly to the "Latest Current Issue" detailed below.



## 3. Latest Current Issue: Cavern VOSpace Node Creation (XML Schema Validation Failure)

This section outlines the current problems affecting the functionality of the Cavern web application. Both issues point to underlying problems with how the Cavern web application is built and deployed.

### 3.1. Cavern VOSpace Node Creation (XML Schema Validation Failure)

* **Problem:** When attempting to create a VOSpace `ContainerNode` using a `PUT` request to Cavern's API, the service returns an `InvalidArgument` error with the message: `XML failed schema validation: Error on line 1: cvc-elt.1.a: Cannot find the declaration of element 'vos:ContainerNode'.`.

* **Details:** This indicates that:
    * The client is sending correctly formatted VOSpace 2.0 XML with the `vos:ContainerNode` element and the `http://www.ivoa.net/xml/VOSpace/v2.0` namespace. This format aligns with VOSpace standards and Cavern's internal `xmlprocessor.java` confirms its expectation of `VOSpace-2.1.xsd` corresponding to this namespace.
    * However, Cavern's internal XML parser is, for an unknown reason, unable to locate or properly recognize the definition of `ContainerNode` within its own loaded VOSpace schema.

* **Current Status:** This is a **server-side problem within the Cavern image's configuration or bundled schema files**, as client-side adjustments to the `xsi:schemaLocation` attribute (or its removal) have not resolved the validation failure. It points to a deeper issue with how Cavern's XML validator processes or accesses its internal schema definitions. We were preparing to investigate this by enabling verbose server-side logging after resolving other immediate issues.

### 3.2. Missing Swagger UI Static Assets

* **Problem:** When accessing the Cavern API homepage (`https://localhost:8443/cavern/`) in a web browser, the page appears unstyled, and the browser's developer console shows numerous `Failed to load resource: the server responded with a status of 404` errors for critical Swagger UI CSS (e.g., `screen.css`, `typography.css`) and JavaScript files (e.g., `jquery-1.8.0.min.js`, `swagger-ui.js`).
* **Context & Initial Fix:** Initially, an `HTTP Status 404 – Not Found` was encountered due to an un-evaluated `${request.servletPath}` placeholder in `index.html`. This was corrected to use a static relative path (`href="/cavern/"`) for the logo link, resolving the immediate link error.
* **Root Cause Identified:** Inspection of the local source code repository (`opencadc/vos/vos-main/cavern/src/main/webapp`) confirmed that the `css/`, `js/`, and `lib/` directories (containing these Swagger UI assets) are missing from the local clone. This indicates these assets are not being correctly packaged into the `cavern.war` file during the Gradle build.

### Overall Summary of Current Issues

Both issues (XML Schema Validation Failure and Missing Swagger UI Assets) point to a fundamental problem with the Cavern web application's build and deployment process. Critical static assets (for Swagger UI) and potentially critical XML schema definition files (for VOSpace validation) are not being consistently included in the final `cavern.war` artifact. This suggests either:
* An incomplete or corrupted local clone of the repository.
* A missing or failing Gradle build step that is supposed to download, generate, or copy these necessary files into the `src/main/webapp` directory before the `.war` is assembled.

Our immediate next step is to address the missing Swagger UI assets by ensuring they are present in the `src/main/webapp` directory, then rebuilding and redeploying Cavern. Once the Swagger UI is functional, we can then proceed with the detailed server-side logging to diagnose the persistent XML schema validation error.


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
