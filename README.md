# Grist deployment

A very opinionated deployment of [Grist](https://www.getgrist.com) with Docker Compose.

> **Warning**  
> For test deployments using a self-signed certificate in Traefik, the `GRIST_NODE_TLS_REJECT_UNAUTHORIZED` variable in the `.env` file must be set to `0`. Please note that this is unsafe and not suitable for production use.
