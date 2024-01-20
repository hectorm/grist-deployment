# Grist deployment

A very opinionated deployment of [Grist](https://www.getgrist.com) with Docker Compose.

> **Warning**  
> Before running the containers it is necessary to run the `./config/traefik/mkcerts.sh` and `./config/authentik/mkcerts.sh` scripts to generate the certificates. They require OpenSSL and should work on any Linux distribution and macOS.
>
> Additionally, for test deployments using a self-signed certificate in Traefik, the `GRIST_NODE_TLS_REJECT_UNAUTHORIZED` variable in the `.env` file must be set to `0`. Please note that this is unsafe and not suitable for production use.
