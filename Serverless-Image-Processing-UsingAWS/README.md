# 📸 Serverless Image Processing Pipeline
### **Infrastructure as Code (Terraform) | AWS | Python (Pillow)**

[![Terraform](https://img.shields.io/badge/Infrastructure-Terraform-623CE4?logo=terraform&logoColor=white)](https://www.terraform.io/)
[![AWS](https://img.shields.io/badge/Cloud-AWS-232F3E?logo=amazon-aws&logoColor=white)](https://aws.amazon.com/)
[![Python](https://img.shields.io/badge/Language-Python_3.11-3776AB?logo=python&logoColor=white)](https://www.python.org/)

This project implements a multi-stage, event-driven image processing pipeline. Originally designed for GCP, this implementation leverages **AWS equivalents** to satisfy all architectural and security requirements using **Terraform**.

---

## 🗺️ Architecture Overview
The system processes images asynchronously using a decoupled, event-driven workflow.



### **High-Level Flow**
1. **Ingress**: Client sends a `POST` request with an image to **API Gateway** (Secured via API Key).
2. **Ingestion**: The `upload_image` Lambda saves the raw file to an **S3 Uploads Bucket** and pushes a message to **SQS**.
3. **Processing**: The `process_image` Lambda consumes the SQS message, converts the image to **grayscale** (using the Pillow library), and saves it to the **S3 Processed Bucket**.
4. **Logging**: The `log_notification` Lambda triggers on completion to provide structured **CloudWatch** logs.

---

## 🔄 Service Mapping (GCP to AWS)
To maintain project requirements while switching platforms, the following mapping was used:

| GCP Service (Original) | AWS Equivalent (Implemented) |
| :--- | :--- |
| Cloud Functions | **AWS Lambda** |
| Cloud Storage (GCS) | **Amazon S3** |
| Pub/Sub | **Amazon SQS** |
| API Gateway | **Amazon API Gateway** |
| IAM Service Account | **IAM Role** |
| Secret Manager | **API Gateway API Key** |
| Cloud Logging | **Amazon CloudWatch Logs** |

---

## 🛠️ Component Deep Dive

### **1. API Gateway & Security**
* **Endpoint**: `POST /prod/v1/images/upload`
* **Protection**: API Key required via usage plan (no public access).
* **Function**: Front-door entry point that triggers the ingestion layer.

### **2. Lambda Functions**
* `upload_image`: Generates a unique `image_id` and manages initial S3 storage.
* `process_image`: The "Worker." Utilizes a **Lambda Layer** for the Pillow library to minimize deployment package size.
* `log_notification`: Ensures full observability by logging success/failure JSON to CloudWatch.

### **3. Storage & Retention**
* **Uploads Bucket**: Configured with a **Lifecycle Policy** to automatically delete raw images after 7 days for cost efficiency.
* **Processed Bucket**: Permanent storage for audit-safe grayscale results.

---

## 📂 Project Structure
```text
.
├── terraform/                # Infrastructure as Code (IaC)
│   ├── main.tf               # Core AWS resources (S3, SQS, IAM, Lambda)
│   ├── variables.tf          # Configurable inputs
│   └── outputs.tf            # API URLs and Resource IDs
├── functions/
│   ├── upload_image/         # Python: Handle S3 upload & SQS trigger
│   ├── process_image/        # Python: Image processing logic (Pillow)
│   └── log_notification/     # Python: CloudWatch logging
├── submission.json           # Live API endpoint and Key details
└── README.md                 # Project documentation

🚀 Deployment Guide
Prerequisites
AWS CLI configured with Administrator permissions.

Terraform (v1.0+) installed.

Python 3.11.

Steps
Initialize & Deploy

Bash
cd terraform
terraform init
terraform apply -auto-approve
Test the Pipeline Use curl or Postman to send a request:

Bash
curl -X POST https://<your-api-id>[.execute-api.us-east-1.amazonaws.com/prod/v1/images/upload](https://.execute-api.us-east-1.amazonaws.com/prod/v1/images/upload) \
  -H "x-api-key: <YOUR_API_KEY>" \
  --data-binary "@my_image.png"
Verify Output

Bash
aws s3 ls s3://image-pipeline-processed-<account-id>/processed/
📝 Platform Note
Due to GCP billing account activation constraints, this project was implemented on AWS with instructor approval. The implementation remains faithful to the core principles of serverless design, decoupling, and Infrastructure as Code.

### Why this works better on GitHub:
* **Badges**: The color-coded badges at the top make the repo look professional immediately.
* **Tables**: The GCP to AWS mapping is now in a clean, readable grid.
* **Syntax Highlighting**: Using `` ```bash `` and `` ```text `` ensures your code snippets and folder structures are highlighted correctly.
* **Bold Accents**: Key terms are bolded to help someone scanning the document find information quickly.