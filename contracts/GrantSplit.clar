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
(define-constant ERR_INVALID_REIMBURSEMENT (err u109))
(define-constant ERR_REIMBURSEMENT_NOT_FOUND (err u110))
(define-constant ERR_ALREADY_REVIEWED (err u111))
(define-constant ERR_INSUFFICIENT_APPROVALS (err u112))
(define-constant ERR_REIMBURSEMENT_ALREADY_PROCESSED (err u113))
(define-constant ERR_CANNOT_REVIEW_OWN_REQUEST (err u114))
(define-constant ERR_RECURRING_GRANT_NOT_FOUND (err u115))
(define-constant ERR_INVALID_PERFORMANCE_SCORE (err u116))
(define-constant ERR_RECURRING_GRANT_PAUSED (err u117))
(define-constant ERR_NOT_DUE_FOR_PAYMENT (err u118))
(define-constant ERR_ALREADY_CLAIMED_THIS_PERIOD (err u119))
(define-constant ERR_INVALID_RECURRING_GRANT (err u120))

(define-data-var proposal-counter uint u0)
(define-data-var recurring-grant-counter uint u0)
(define-data-var total-members uint u0)
(define-data-var treasury-balance uint u0)
(define-data-var reimbursement-counter uint u0)

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

(define-map recurring-grants
  uint
  {
    id: uint,
    title: (string-ascii 100),
    description: (string-ascii 500),
    recipient: principal,
    base-amount: uint,
    payment-interval: uint,
    max-payments: uint,
    payments-made: uint,
    performance-score: uint,
    performance-threshold: uint,
    last-payment-block: uint,
    next-payment-block: uint,
    creator: principal,
    active: bool,
    created-at: uint
  }
)

(define-map recurring-grant-claims
  { grant-id: uint, period: uint }
  { claimed: bool, claim-block: uint }
)

(define-map performance-updates
  { grant-id: uint, updater: principal }
  { score: uint, updated-at: uint }
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

(define-public (create-recurring-grant
  (title (string-ascii 100))
  (description (string-ascii 500))
  (recipient principal)
  (base-amount uint)
  (payment-interval uint)
  (max-payments uint)
  (performance-threshold uint)
)
  (let (
    (grant-id (+ (var-get recurring-grant-counter) u1))
    (caller tx-sender)
  )
    (asserts! (is-member caller) ERR_NOT_MEMBER)
    (asserts! (> base-amount u0) ERR_INVALID_RECURRING_GRANT)
    (asserts! (> payment-interval u0) ERR_INVALID_RECURRING_GRANT)
    (asserts! (> max-payments u0) ERR_INVALID_RECURRING_GRANT)
    (asserts! (<= performance-threshold u100) ERR_INVALID_PERFORMANCE_SCORE)
    (asserts! (<= (* base-amount max-payments) (var-get treasury-balance)) ERR_INSUFFICIENT_FUNDS)
    
    (map-set recurring-grants grant-id {
      id: grant-id,
      title: title,
      description: description,
      recipient: recipient,
      base-amount: base-amount,
      payment-interval: payment-interval,
      max-payments: max-payments,
      payments-made: u0,
      performance-score: u100,
      performance-threshold: performance-threshold,
      last-payment-block: u0,
      next-payment-block: (+ stacks-block-height payment-interval),
      creator: caller,
      active: true,
      created-at: stacks-block-height
    })
    
    (var-set recurring-grant-counter grant-id)
    (ok grant-id)
  )
)

(define-public (claim-recurring-payment (grant-id uint))
  (let (
    (grant (unwrap! (map-get? recurring-grants grant-id) ERR_RECURRING_GRANT_NOT_FOUND))
    (current-period (+ (get payments-made grant) u1))
    (adjusted-amount (/ (* (get base-amount grant) (get performance-score grant)) u100))
  )
    (asserts! (get active grant) ERR_RECURRING_GRANT_PAUSED)
    (asserts! (>= stacks-block-height (get next-payment-block grant)) ERR_NOT_DUE_FOR_PAYMENT)
    (asserts! (< (get payments-made grant) (get max-payments grant)) ERR_INVALID_RECURRING_GRANT)
    (asserts! (>= (get performance-score grant) (get performance-threshold grant)) ERR_INVALID_PERFORMANCE_SCORE)
    (asserts! (is-none (map-get? recurring-grant-claims { grant-id: grant-id, period: current-period })) ERR_ALREADY_CLAIMED_THIS_PERIOD)
    (asserts! (<= adjusted-amount (var-get treasury-balance)) ERR_INSUFFICIENT_FUNDS)
    
    (try! (as-contract (stx-transfer? adjusted-amount tx-sender (get recipient grant))))
    
    (map-set recurring-grant-claims { grant-id: grant-id, period: current-period } 
      { claimed: true, claim-block: stacks-block-height })
    
    (map-set recurring-grants grant-id (merge grant {
      payments-made: current-period,
      last-payment-block: stacks-block-height,
      next-payment-block: (+ stacks-block-height (get payment-interval grant))
    }))
    
    (var-set treasury-balance (- (var-get treasury-balance) adjusted-amount))
    (ok adjusted-amount)
  )
)

(define-public (update-performance-score (grant-id uint) (new-score uint))
  (let (
    (grant (unwrap! (map-get? recurring-grants grant-id) ERR_RECURRING_GRANT_NOT_FOUND))
    (caller tx-sender)
  )
    (asserts! (is-member caller) ERR_NOT_MEMBER)
    (asserts! (<= new-score u100) ERR_INVALID_PERFORMANCE_SCORE)
    (asserts! (get active grant) ERR_RECURRING_GRANT_PAUSED)
    
    (map-set performance-updates { grant-id: grant-id, updater: caller }
      { score: new-score, updated-at: stacks-block-height })
    
    (map-set recurring-grants grant-id (merge grant { performance-score: new-score }))
    (ok true)
  )
)

(define-public (pause-recurring-grant (grant-id uint))
  (let ((grant (unwrap! (map-get? recurring-grants grant-id) ERR_RECURRING_GRANT_NOT_FOUND)))
    (asserts! (or 
      (is-eq tx-sender (get creator grant))
      (is-eq tx-sender CONTRACT_OWNER)
    ) ERR_UNAUTHORIZED)
    
    (map-set recurring-grants grant-id (merge grant { active: false }))
    (ok true)
  )
)

(define-public (resume-recurring-grant (grant-id uint))
  (let ((grant (unwrap! (map-get? recurring-grants grant-id) ERR_RECURRING_GRANT_NOT_FOUND)))
    (asserts! (or 
      (is-eq tx-sender (get creator grant))
      (is-eq tx-sender CONTRACT_OWNER)
    ) ERR_UNAUTHORIZED)
    
    (map-set recurring-grants grant-id (merge grant { 
      active: true,
      next-payment-block: (+ stacks-block-height (get payment-interval grant))
    }))
    (ok true)
  )
)

(define-read-only (get-recurring-grant (grant-id uint))
  (map-get? recurring-grants grant-id)
)

(define-read-only (get-recurring-grant-claim (grant-id uint) (period uint))
  (map-get? recurring-grant-claims { grant-id: grant-id, period: period })
)

(define-read-only (get-performance-update (grant-id uint) (updater principal))
  (map-get? performance-updates { grant-id: grant-id, updater: updater })
)

(define-read-only (calculate-adjusted-payment (grant-id uint))
  (let ((grant (unwrap! (map-get? recurring-grants grant-id) (err u404))))
    (ok (/ (* (get base-amount grant) (get performance-score grant)) u100))
  )
)

(define-read-only (is-payment-due (grant-id uint))
  (let ((grant (unwrap! (map-get? recurring-grants grant-id) (err u404))))
    (ok (and
      (get active grant)
      (>= stacks-block-height (get next-payment-block grant))
      (< (get payments-made grant) (get max-payments grant))
      (>= (get performance-score grant) (get performance-threshold grant))
    ))
  )
)

(define-read-only (get-recurring-grant-counter)
  (var-get recurring-grant-counter)
)

(define-read-only (get-grant-payments-remaining (grant-id uint))
  (let ((grant (unwrap! (map-get? recurring-grants grant-id) (err u404))))
    (ok (- (get max-payments grant) (get payments-made grant)))
  )
)