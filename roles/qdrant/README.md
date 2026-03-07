# Role: qdrant

## Purpose

Deploy Qdrant vector database for retrieval-augmented generation (RAG) in Open WebUI.

## Container Configuration

| Setting      | Value                              |
|--------------|------------------------------------|
| Image        | `qdrant/qdrant:latest`            |
| HTTP port    | `6333`                             |
| gRPC port    | `6334`                             |
| Volume       | `/mnt/ai_data/qdrant:/qdrant/storage` |

## Integration with Open WebUI

Open WebUI is configured to use Qdrant as its vector database backend:

| Open WebUI Env Var | Value                          |
|--------------------|--------------------------------|
| `VECTOR_DB`        | `qdrant`                       |
| `QDRANT_URI`       | `http://host.docker.internal:6333` |

## Collections

Collections are auto-managed by Open WebUI. When a user uploads documents or enables
RAG for a conversation, Open WebUI automatically creates and populates the necessary
Qdrant collections. No manual collection management is required.

## Backup

To back up the Qdrant data:

```bash
# Stop the container to ensure data consistency
docker stop qdrant

# Archive the data directory
tar -czf qdrant_backup_$(date +%Y%m%d).tar.gz /mnt/ai_data/qdrant

# Restart the container
docker start qdrant
```

## Tags

```bash
ansible-playbook playbooks/site.yml --tags qdrant
```
