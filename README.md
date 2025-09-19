# Medical Record Management System

## Overview

A secure and private blockchain-based system for managing medical records and enabling controlled sharing between healthcare providers. This system prioritizes patient privacy while facilitating authorized access to medical data by qualified healthcare professionals.

## Architecture

The system consists of two primary smart contracts:

### 1. Patient Consent Contract
- **Purpose**: Manages patient consent for data sharing
- **Key Features**:
  - Patient-controlled consent management
  - Granular permission settings for different data types
  - Revocable consent mechanisms
  - Audit trail for consent changes

### 2. Access Control Contract
- **Purpose**: Implements role-based access control for medical professionals
- **Key Features**:
  - Role-based permission system
  - Healthcare provider verification
  - Access logging and monitoring
  - Emergency access protocols

## Security Features

- **Data Privacy**: All sensitive data is encrypted and stored off-chain with only references on the blockchain
- **Consent Verification**: Every data access request requires verified patient consent
- **Audit Trails**: Complete logging of all access attempts and data sharing activities
- **Role Verification**: Healthcare providers must be verified before gaining access to patient data

## Use Cases

1. **Hospital-to-Hospital Transfers**: Secure transfer of patient records during referrals
2. **Emergency Medical Access**: Controlled emergency access to critical patient information
3. **Research Participation**: Patient-controlled data sharing for approved medical research
4. **Insurance Claims**: Authorized sharing of medical records for insurance processing

## Technology Stack

- **Blockchain Platform**: Stacks (STX)
- **Smart Contract Language**: Clarity
- **Development Framework**: Clarinet

## Smart Contracts

### Patient Consent
- Manages patient consent preferences
- Tracks consent history and changes
- Provides consent verification functions

### Access Control
- Defines healthcare provider roles and permissions
- Manages access requests and approvals
- Implements emergency access protocols

## Getting Started

### Prerequisites
- Clarinet CLI installed
- Node.js (version 16 or higher)
- Git

### Installation

1. Clone the repository:
   ```bash
   git clone https://github.com/estherrachelle022/medical-record-management.git
   cd medical-record-management
   ```

2. Install dependencies:
   ```bash
   npm install
   ```

3. Run contract checks:
   ```bash
   clarinet check
   ```

4. Run tests:
   ```bash
   clarinet test
   ```

## Contract Deployment

### Testnet Deployment
```bash
clarinet publish --testnet
```

### Mainnet Deployment
```bash
clarinet publish --mainnet
```

## API Documentation

### Patient Consent Contract Functions

#### `grant-consent`
Grants consent for a specific healthcare provider to access patient data.
- **Parameters**: `provider-id`, `data-type`, `expiration`
- **Returns**: Success/Error response

#### `revoke-consent`
Revokes previously granted consent.
- **Parameters**: `provider-id`, `data-type`
- **Returns**: Success/Error response

#### `check-consent`
Verifies if consent exists for a specific access request.
- **Parameters**: `patient-id`, `provider-id`, `data-type`
- **Returns**: Boolean consent status

### Access Control Contract Functions

#### `register-provider`
Registers a new healthcare provider in the system.
- **Parameters**: `provider-info`, `role`, `credentials`
- **Returns**: Provider ID

#### `request-access`
Requests access to patient data.
- **Parameters**: `patient-id`, `data-type`, `purpose`
- **Returns**: Access token/denial

#### `verify-provider`
Verifies healthcare provider credentials.
- **Parameters**: `provider-id`
- **Returns**: Verification status

## Contributing

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Add tests for new functionality
5. Submit a pull request

## Compliance

This system is designed with healthcare compliance in mind, including:
- HIPAA privacy requirements
- Data portability standards
- Patient rights protection
- Healthcare interoperability guidelines

## License

This project is licensed under the MIT License - see the LICENSE file for details.

## Support

For technical support or questions, please open an issue in the GitHub repository.

## Roadmap

- [ ] Integration with major Electronic Health Record (EHR) systems
- [ ] Mobile application for patient consent management
- [ ] Advanced analytics dashboard for healthcare providers
- [ ] International compliance framework support
- [ ] Multi-language support