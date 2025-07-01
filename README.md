Ska-Cavern Development Environment
This README outlines the setup and troubleshooting steps for the Ska-Cavern development environment, which includes services like Cavern (VOSpace implementation), PosixMapper (for POSIX user/group mapping), HAProxy (SSL termination), Nginx proxies, RabbitMQ, and PostgreSQL databases.

0. Prerequisites / Dependencies
This project relies on additional external repositories for its build contexts. Please ensure you have cloned the following repositories/directories into your home directory (${HOME}) before building and running the Docker Compose environment:

ska-src-dm-local-data-preparer: This repository is the source for the core application and celery-worker. Ensure it is cloned into ~/ska-src-dm-local-data-preparer.

cavern-code/vos/cavern: This directory within a cavern-code repository is the build context for the cavern service. Ensure you clone cavern-code and that the vos/cavern path exists within it (e.g., ~/cavern-code/vos/cavern).

1. Services Overview
The docker-compose.yml orchestrates the following key services:

core: The main data preparer application.

celery-worker: Handles asynchronous tasks for data preparation.

rabbitmq: Message broker for Celery.

postgres_cavern: PostgreSQL database for Cavern's UWS.

postgres_posixmapper: PostgreSQL database for PosixMapper.

haproxy: SSL termination and reverse proxy for cavern and posixmapper-proxy.

posixmapper-proxy: Nginx proxy for posixmapper capabilities and routing.

posixmapper: Service for POSIX user/group mapping.

registrymock: Mock IVOA Registry and OIDC provider.

2. Steps Taken to Get Services Working
This section details the step-by-step troubleshooting process undertaken to get the various services in the Ska-Cavern environment to a functional state.

2.1. HAProxy and Registry Mock Setup
HAProxy Role: Configured for SSL termination and acting as a reverse proxy. It routes external HTTPS traffic on host port 8443 to internal HTTP services like cavern and posixmapper-proxy.

Registry Mock Role: Functions as a mock IVOA Registry service, providing static capabilities XML and OpenID Connect (OIDC) endpoints.

Confirmation: These services were configured correctly from the outset and did not require specific troubleshooting steps for their core functionality. Their successful operation was implicitly confirmed as other dependent services (like cavern and posixmapper-proxy) were able to communicate through them without errors directly related to haproxy or registrymock connectivity. For instance, cavern successfully imported haproxy.crt and configured its PosixMapperClient with a URL routed through haproxy.

2.2. PosixMapper Database Connectivity Issues (Primary Blocker)
Problem: Upon initial review of docker compose logs posixmapper, the service failed to start its database connection pool due to java.lang.NumberFormatException: For input string: "${org.opencadc.posix.mapper.maxActive}" and a critical cp: cannot stat '/tmp/config/context.xml': No such file or directory error.

Diagnosis: This indicated that placeholders in posixmapper's Tomcat context.xml were not being resolved. The cp error suggested that the intended context.xml file, which defines these properties, was not being successfully copied into the container's application directory during startup, leaving the default, unconfigured context.xml from the WAR file in use.

Resolution Step 1: Direct context.xml Mount: The docker-compose.yml was modified to directly mount the host's config/posixmapper/META-INF/context.xml to the final unpacked location within the container: - ./config/posixmapper/META-INF/context.xml:/usr/share/tomcat/webapps/posix-mapper/META-INF/context.xml:ro. The resulting "Device or resource busy" message during WAR unpacking confirmed this mount was active.

Resolution Step 2: Hardcode Database URL: Despite the direct mount, posixmapper still failed with java.sql.SQLException: Driver:... returned null for URL:${system.POSIX_MAPPER_URL}. To bypass this property substitution issue, the url attribute in config/posixmapper/META-INF/context.xml was hardcoded to jdbc:postgresql://postgres_posixmapper:5432/mapping.

Resolution Step 3: Hardcode Username and Password: Following the URL fix, posixmapper reported FATAL: password authentication failed for user "${system.POSIX_MAPPER_USERNAME}". Similarly, the username and password attributes in config/posixmapper/META-INF/context.xml were hardcoded to posixmapper and posixmapperpwd respectively.

Outcome of PosixMapper Fixes: posixmapper successfully connected to its database, completed initialization, and became fully functional.

2.3. Cavern Service Initialization & VOSpace NodeNotFound Error
Cavern Startup: Throughout the troubleshooting, cavern consistently reported successful startup of its Tomcat application, successful certificate import via cavern_init_cert.sh, and correct initialization of its UWS database.

User Mapping Observation: Once posixmapper was stable, cavern successfully communicated with it for user mapping. For example, during a request for /home/testuser, cavern logs showed successful resolution of PosixPrincipal [uidNumber=10000,10000,testuser], indicating successful integration.

Initial VOSpace Problem: Initial attempts to GET VOSpace nodes (e.g., /home/testuser) resulted in a ca.nrc.cadc.net.ResourceNotFoundException: NodeNotFound: vos://localhost~cavern_test_instance/home/testuser error. This NodeNotFound error was expected, as the VOSpace path did not yet exist in Cavern's underlying data storage (./data/cavern_files). This confirmed core services were communicating.

Solution Attempt (leading to current issue): An attempt to create the ContainerNode via a PUT request with an XML payload was made. This led directly to the "Latest Current Issue" detailed below.

3. Latest Current Issue: Cavern VOSpace Node Creation (XML Schema Validation Failure)
Problem:
When attempting to create a VOSpace ContainerNode using a PUT request to Cavern's API, the service returns an InvalidArgument error with the message: XML failed schema validation: Error on line 1: cvc-elt.1.a: Cannot find the declaration of element 'vos:ContainerNode'..

Details:
This indicates that:

The client is sending correctly formatted VOSpace 2.0 XML with the vos:ContainerNode element and the http://www.ivoa.net/xml/VOSpace/v2.0 namespace. This format aligns with VOSpace standards and Cavern's internal xmlprocessor.java confirms its expectation of VOSpace-2.1.xsd corresponding to this namespace.

However, Cavern's internal XML parser is, for an unknown reason, unable to locate or properly recognize the definition of ContainerNode within its own loaded VOSpace schema.

This is a server-side problem within the Cavern image's configuration or bundled schema files, as client-side adjustments to the xsi:schemaLocation attribute (or its removal) have not resolved the validation failure. It points to a deeper issue with how Cavern's XML validator processes or accesses its internal schema definitions.

4. curl Commands for Verification and Operations
You will need a valid Bearer token for authenticated requests.

4.1. Check Cavern Capabilities
Verifies that the Cavern VOSpace capabilities are accessible. This should return an XML document describing the service's features.

Bash

curl -k https://localhost:8443/cavern/capabilities
4.2. Submit Latest Job to Data Preparer (Core Service)
This command triggers a data preparation task in the core service. It should return a task_id.

Bash

curl -X POST \
  -H 'Content-Type: application/json' \
  -H 'Authorization: Bearer eyJ0eXAiOiJKV1QiLCJhbGciOiJIUzI1NiJ9.eyJwcmVmZXJyZWRfdXNlcm5hbWUiOiJ0ZXN0dXNlciIsInN1YiI6ImxvY2FsdGVzdHVzZXJfaWQiLCJpYXQiOjE3NTAyOTU2OTAsImV4cCI6MTc1MDI5OTI5MH0.4lBmhoazmEiUjJRvWxdZTkEYKHUsQKVp9CtPZ-crz0Y' \
  -d '[
        ["testing:prepare_data_test.txt", "testing/84/1c/prepare_data_test.txt", "./testing"]
      ]' \
  http://localhost:8000/
4.3. Attempt to Create a VOSpace Node (Reproduces Latest Error)
This curl command attempts to create the /home/testuser VOSpace ContainerNode and will reproduce the current XML schema validation error.

Bash

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
