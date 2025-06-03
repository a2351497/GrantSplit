# 🏛️ GrantSplit - Decentralized Grant Allocation DAO

## 📋 Overview

GrantSplit is a **voting-based NGO funding platform** built on Stacks blockchain using Clarity smart contracts. It enables decentralized communities to collectively decide how to allocate grant funds through transparent democratic voting processes.

## ✨ Key Features

- 🗳️ **Democratic Voting**: Members vote on funding proposals with weighted voting power
- 💰 **Treasury Management**: Secure fund deposits and automated disbursements
- 📊 **Transparent Governance**: All proposals and votes are recorded on-chain
- 🔒 **Secure Execution**: Proposals only execute after meeting quorum and majority approval
- 👥 **Membership System**: Join the DAO and participate in funding decisions

## 🚀 Getting Started

### Prerequisites
- Clarinet CLI installed
- Stacks wallet for testing

### Installation

```bash
git clone <your-repo>
cd grantsplit
clarinet check
```

## 📖 Usage Guide

### 1. 👤 Join the DAO
```clarity
(contract-call? .GrantSplit join-dao)
```

### 2. 💵 Deposit Funds to Treasury
```clarity
(contract-call? .GrantSplit deposit-funds u1000000) ;; 1 STX
```

### 3. 📝 Create a Funding Proposal
```clarity
(contract-call? .GrantSplit create-proposal 
  "Education Initiative" 
  "Fund coding bootcamp for underserved communities"
  'SP2J6ZY48GV1EZ5V2V5RB9MP66SW86PYKKNRV9EJ7
  u500000  ;; 0.5 STX
  u144     ;; ~24 hours voting period
)
```

### 4. 🗳️ Vote on Proposals
```clarity
;; Vote FOR proposal #1
(contract-call? .GrantSplit vote-on-proposal u1 true)

;; Vote AGAINST proposal #1  
(contract-call? .GrantSplit vote-on-proposal u1 false)
```

### 5. ⚡ Execute Approved Proposals
```clarity
(contract-call? .GrantSplit execute-proposal u1)
```

## 🔍 Read-Only Functions

### Check Proposal Details
```clarity
(contract-call? .GrantSplit get-proposal u1)
(contract-call? .GrantSplit get-proposal-status u1)
```

### View Treasury & Membership
```clarity
(contract-call? .GrantSplit get-treasury-balance)
(contract-call? .GrantSplit get-total-members)
(contract-call? .GrantSplit is-member 'SP2J6ZY48GV1EZ5V2V5RB9MP66SW86PYKKNRV9EJ7)
```

## 🏗️ Contract Architecture

### Core Components
- **Membership Management**: Join DAO and manage voting power
- **Proposal System**: Create, vote on, and execute funding proposals  
- **Treasury**: Secure fund management with automated disbursements
- **Governance**: Quorum requirements and majority voting rules

### Voting Rules
- ✅ **Quorum**: 50% of total members must participate
- ✅ **Majority**: More votes FOR than AGAINST required
- ✅ **One Vote**: Each member votes once per proposal
- ⏰ **Time Limit**: Voting ends after specified block duration

## 🛡️ Security Features

- 🔐 Only members can create proposals and vote
- 💸 Proposals cannot exceed treasury balance
- 🚫 Double voting prevention
- ⏱️ Time-locked proposal execution
- 🎯 Automated fund transfers only after approval

## 🧪 Testing

```bash
clarinet test
```

## 🤝 Contributing

1. Fork the repository
2. Create your feature branch
3. Commit your changes  
4. Push to the branch
5. Create a Pull Request

## 📄 License

MIT License - see LICENSE file for details

---

**Built with ❤️ for decentralized communities seeking transparent grant allocation**

