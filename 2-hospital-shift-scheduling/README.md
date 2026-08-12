\# Project: Automated Hospital Shift Scheduling \& Report Generation Engine



\## 🎯 Overview

This repository contains an enterprise-grade automation solution developed in \*\*n8n\*\* designed to handle complex, recurring operational workflows for healthcare institutions. The system replaces manual administrative effort by querying a centralized Google Sheets database and autonomously generating, formatting, and populating 17 distinct departmental work schedule files every single month.



The solution eliminates scheduling errors, reduces administrative latency to zero, and ensures strict compliance with institutional shift distributions.



\---



\## ⚙️ Core Logic \& Business Workflow

\*   \*\*Centralized Master Database:\*\* Operates from a master Google Sheets database containing comprehensive records of physicians, medical exams, and operational hours.

\*   \*\*Automated Monthly Cycle Execution:\*\* Triggered on a scheduled recurring basis to execute the end-to-end monthly closing and generation cycle.

\*   \*\*Cloud Drive Provisioning:\*\* Automatically provisions structured folder hierarchies on Google Drive for the new operational period.

\*   \*\*Multi-File Generation \& Population:\*\* Dynamically generates 17 distinct spreadsheet files (one for each specific hospital department/sector) and accurately populates them with correct calendar dates, assigned professionals, and exam slots.



\---



\## 🛠️ Technology Stack \& Architecture

\*   \*\*Orchestration \& Infrastructure:\*\* n8n (Self-hosted on Hostinger KVM 2 VPS / Enterprise architecture)

\*   \*\*Cloud Storage \& Data Sources:\*\* Google Drive API \& Google Sheets API (Master database architecture and automated file management)

\*   \*\*Custom Code \& Logic:\*\* Advanced \*\*JavaScript / TypeScript\*\* code nodes for matrix data manipulation, array mapping, date math, and dynamic payload transformation.

\*   \*\*Security \& Compliance:\*\* Secure OAuth2 credential isolation and scoped service accounts ensuring compliance with healthcare data management standards.

