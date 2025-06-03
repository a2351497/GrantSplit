(define-constant CONTRACT_OWNER tx-sender)
(define-constant ERR_UNAUTHORIZED (err u100))
(define-constant ERR_INVALID_PROPOSAL (err u101))
(define-constant ERR_VOTING_ENDED (err u102))
(define-constant ERR_VOTING_ACTIVE (err u103))
(define-constant ERR_ALREADY_VOTED (err u104))
(define-constant ERR_INSUFFICIENT_FUNDS (err u105))
(define-constant ERR_PROPOSAL_NOT_PASSED (err u106))
(define-constant ERR_ALREADY_EXECUTED (err u107))
(define-constant ERR_NOT_MEMBER (err u108))

(define-data-var proposal-counter uint u0)
(define-data-var total-members uint u0)
(define-data-var treasury-balance uint u0)

(define-map dao-members principal bool)
(define-map member-voting-power principal uint)

(define-map proposals
  uint
  {
    id: uint,
    title: (string-ascii 100),
    description: (string-ascii 500),
    recipient: principal,
    amount: uint,
    proposer: principal,
    votes-for: uint,
    votes-against: uint,
    voting-end-block: uint,
    executed: bool,
    created-at: uint
  }
)

(define-map proposal-votes
  { proposal-id: uint, voter: principal }
  { vote: bool, voting-power: uint }
)

(define-public (join-dao)
  (let ((caller tx-sender))
    (if (is-member caller)
      (err u109)
      (begin
        (map-set dao-members caller true)
        (map-set member-voting-power caller u1)
        (var-set total-members (+ (var-get total-members) u1))
        (ok true)
      )
    )
  )
)

(define-public (deposit-funds (amount uint))
  (begin
    (try! (stx-transfer? amount tx-sender (as-contract tx-sender)))
    (var-set treasury-balance (+ (var-get treasury-balance) amount))
    (ok true)
  )
)

(define-public (create-proposal 
  (title (string-ascii 100))
  (description (string-ascii 500))
  (recipient principal)
  (amount uint)
  (voting-duration uint)
)
  (let (
    (proposal-id (+ (var-get proposal-counter) u1))
    (caller tx-sender)
  )
    (asserts! (is-member caller) ERR_NOT_MEMBER)
    (asserts! (> amount u0) ERR_INVALID_PROPOSAL)
    (asserts! (<= amount (var-get treasury-balance)) ERR_INSUFFICIENT_FUNDS)
    
    (map-set proposals proposal-id {
      id: proposal-id,
      title: title,
      description: description,
      recipient: recipient,
      amount: amount,
      proposer: caller,
      votes-for: u0,
      votes-against: u0,
      voting-end-block: (+ stacks-block-height voting-duration),
      executed: false,
      created-at: stacks-block-height
    })
    
    (var-set proposal-counter proposal-id)
    (ok proposal-id)
  )
)

(define-public (vote-on-proposal (proposal-id uint) (vote-for bool))
  (let (
    (caller tx-sender)
    (proposal (unwrap! (map-get? proposals proposal-id) ERR_INVALID_PROPOSAL))
    (voting-power (default-to u0 (map-get? member-voting-power caller)))
  )
    (asserts! (is-member caller) ERR_NOT_MEMBER)
    (asserts! (< stacks-block-height (get voting-end-block proposal)) ERR_VOTING_ENDED)
    (asserts! (is-none (map-get? proposal-votes { proposal-id: proposal-id, voter: caller })) ERR_ALREADY_VOTED)
    
    (map-set proposal-votes 
      { proposal-id: proposal-id, voter: caller }
      { vote: vote-for, voting-power: voting-power }
    )
    
    (if vote-for
      (map-set proposals proposal-id 
        (merge proposal { votes-for: (+ (get votes-for proposal) voting-power) })
      )
      (map-set proposals proposal-id 
        (merge proposal { votes-against: (+ (get votes-against proposal) voting-power) })
      )
    )
    
    (ok true)
  )
)

(define-public (execute-proposal (proposal-id uint))
  (let (
    (proposal (unwrap! (map-get? proposals proposal-id) ERR_INVALID_PROPOSAL))
    (total-votes (+ (get votes-for proposal) (get votes-against proposal)))
    (required-quorum (/ (var-get total-members) u2))
  )
    (asserts! (>= stacks-block-height (get voting-end-block proposal)) ERR_VOTING_ACTIVE)
    (asserts! (not (get executed proposal)) ERR_ALREADY_EXECUTED)
    (asserts! (>= total-votes required-quorum) ERR_PROPOSAL_NOT_PASSED)
    (asserts! (> (get votes-for proposal) (get votes-against proposal)) ERR_PROPOSAL_NOT_PASSED)
    (asserts! (<= (get amount proposal) (var-get treasury-balance)) ERR_INSUFFICIENT_FUNDS)
    
    (try! (as-contract (stx-transfer? (get amount proposal) tx-sender (get recipient proposal))))
    
    (map-set proposals proposal-id (merge proposal { executed: true }))
    (var-set treasury-balance (- (var-get treasury-balance) (get amount proposal)))
    
    (ok true)
  )
)

(define-public (increase-voting-power (member principal) (additional-power uint))
  (let ((current-power (default-to u0 (map-get? member-voting-power member))))
    (asserts! (is-eq tx-sender CONTRACT_OWNER) ERR_UNAUTHORIZED)
    (asserts! (is-member member) ERR_NOT_MEMBER)
    
    (map-set member-voting-power member (+ current-power additional-power))
    (ok true)
  )
)

(define-read-only (get-proposal (proposal-id uint))
  (map-get? proposals proposal-id)
)

(define-read-only (get-proposal-vote (proposal-id uint) (voter principal))
  (map-get? proposal-votes { proposal-id: proposal-id, voter: voter })
)

(define-read-only (is-member (address principal))
  (default-to false (map-get? dao-members address))
)

(define-read-only (get-member-voting-power (member principal))
  (default-to u0 (map-get? member-voting-power member))
)

(define-read-only (get-treasury-balance)
  (var-get treasury-balance)
)

(define-read-only (get-total-members)
  (var-get total-members)
)

(define-read-only (get-proposal-counter)
  (var-get proposal-counter)
)

(define-read-only (get-proposal-status (proposal-id uint))
  (let ((proposal (unwrap! (map-get? proposals proposal-id) (err u404))))
    (ok {
      id: (get id proposal),
      title: (get title proposal),
      votes-for: (get votes-for proposal),
      votes-against: (get votes-against proposal),
      voting-ended: (>= stacks-block-height (get voting-end-block proposal)),
      executed: (get executed proposal),
      passed: (> (get votes-for proposal) (get votes-against proposal))
    })
  )
)

(define-read-only (can-execute-proposal (proposal-id uint))
  (let (
    (proposal (unwrap! (map-get? proposals proposal-id) (err u404)))
    (total-votes (+ (get votes-for proposal) (get votes-against proposal)))
    (required-quorum (/ (var-get total-members) u2))
  )
    (ok (and
      (>= stacks-block-height (get voting-end-block proposal))
      (not (get executed proposal))
      (>= total-votes required-quorum)
      (> (get votes-for proposal) (get votes-against proposal))
      (<= (get amount proposal) (var-get treasury-balance))
    ))
  )
)