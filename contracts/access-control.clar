;; title: access-control
;; Role-based access control for medical professionals
;; Manages access permissions and provider verification for medical record systems

;; Error codes
(define-constant ERR-UNAUTHORIZED (err u200))
(define-constant ERR-NOT-FOUND (err u201))
(define-constant ERR-ALREADY-EXISTS (err u202))
(define-constant ERR-INVALID-ROLE (err u203))
(define-constant ERR-INSUFFICIENT-PERMISSIONS (err u204))
(define-constant ERR-ACCESS-DENIED (err u205))

;; Role constants
(define-constant ROLE-ADMIN u1)
(define-constant ROLE-DOCTOR u2)
(define-constant ROLE-NURSE u3)
(define-constant ROLE-TECHNICIAN u4)
(define-constant ROLE-RESEARCHER u5)
(define-constant ROLE-EMERGENCY u6)

;; Contract owner for admin operations
(define-data-var contract-owner principal tx-sender)

;; Provider registry
(define-map healthcare-providers
  { provider: principal }
  {
    role: uint,
    license-number: (string-ascii 50),
    institution: (string-ascii 100),
    registered-at: uint,
    verified: bool,
    active: bool,
    specialization: (string-ascii 50)
  }
)

;; Access requests tracking
(define-map access-requests
  { request-id: uint }
  {
    provider: principal,
    patient: principal,
    data-type: (string-ascii 50),
    purpose: (string-ascii 200),
    requested-at: uint,
    status: (string-ascii 20),
    approved-by: (optional principal)
  }
)

;; Access logs for audit trail
(define-map access-logs
  { log-id: uint }
  {
    provider: principal,
    patient: principal,
    data-type: (string-ascii 50),
    action: (string-ascii 30),
    timestamp: uint,
    authorized: bool
  }
)

;; Emergency access tracking
(define-map emergency-access
  { provider: principal, patient: principal }
  {
    activated-at: uint,
    expires-at: uint,
    reason: (string-ascii 200),
    active: bool
  }
)

;; Counters for IDs
(define-data-var next-request-id uint u0)
(define-data-var next-log-id uint u0)

;; Helper functions
(define-private (is-valid-role (role uint))
  (and (>= role ROLE-ADMIN) (<= role ROLE-EMERGENCY))
)

(define-private (is-admin (provider principal))
  (match (map-get? healthcare-providers { provider: provider })
    provider-data
    (is-eq (get role provider-data) ROLE-ADMIN)
    false
  )
)

(define-private (is-provider-verified (provider principal))
  (match (map-get? healthcare-providers { provider: provider })
    provider-data
    (and (get verified provider-data) (get active provider-data))
    false
  )
)

(define-private (log-access-attempt (provider principal) (patient principal) (data-type (string-ascii 50)) (action (string-ascii 30)) (authorized bool))
  (let ((log-id (var-get next-log-id)))
    (map-set access-logs
      { log-id: log-id }
      {
        provider: provider,
        patient: patient,
        data-type: data-type,
        action: action,
        timestamp: block-height,
        authorized: authorized
      }
    )
    (var-set next-log-id (+ log-id u1))
    true
  )
)

(define-private (can-access-data-type (role uint) (data-type (string-ascii 50)))
  (or
    (is-eq role ROLE-ADMIN)
    (is-eq role ROLE-EMERGENCY)
    (and (is-eq role ROLE-DOCTOR) 
         (or (is-eq data-type "medical-records")
             (is-eq data-type "lab-results")
             (is-eq data-type "prescriptions")
             (is-eq data-type "imaging")
             (is-eq data-type "all")))
    (and (is-eq role ROLE-NURSE)
         (or (is-eq data-type "medical-records")
             (is-eq data-type "lab-results")
             (is-eq data-type "prescriptions")))
    (and (is-eq role ROLE-TECHNICIAN)
         (or (is-eq data-type "lab-results")
             (is-eq data-type "imaging")))
    (and (is-eq role ROLE-RESEARCHER)
         (is-eq data-type "lab-results"))
  )
)

;; Public functions

;; Register a healthcare provider
(define-public (register-provider (provider principal) (role uint) (license-number (string-ascii 50)) (institution (string-ascii 100)) (specialization (string-ascii 50)))
  (begin
    (asserts! (is-eq tx-sender (var-get contract-owner)) ERR-UNAUTHORIZED)
    (asserts! (is-valid-role role) ERR-INVALID-ROLE)
    (asserts! (is-none (map-get? healthcare-providers { provider: provider })) ERR-ALREADY-EXISTS)
    
    (map-set healthcare-providers
      { provider: provider }
      {
        role: role,
        license-number: license-number,
        institution: institution,
        registered-at: block-height,
        verified: false,
        active: true,
        specialization: specialization
      }
    )
    
    (ok true)
  )
)

;; Verify a healthcare provider
(define-public (verify-provider (provider principal))
  (begin
    (asserts! (is-admin tx-sender) ERR-UNAUTHORIZED)
    
    (match (map-get? healthcare-providers { provider: provider })
      provider-data
      (begin
        (map-set healthcare-providers
          { provider: provider }
          (merge provider-data { verified: true })
        )
        (ok true)
      )
      ERR-NOT-FOUND
    )
  )
)

;; Request access to patient data
(define-public (request-access (patient principal) (data-type (string-ascii 50)) (purpose (string-ascii 200)))
  (let ((request-id (var-get next-request-id)))
    (asserts! (is-provider-verified tx-sender) ERR-UNAUTHORIZED)
    
    (match (map-get? healthcare-providers { provider: tx-sender })
      provider-data
      (begin
        (asserts! (can-access-data-type (get role provider-data) data-type) ERR-INSUFFICIENT-PERMISSIONS)
        
        (map-set access-requests
          { request-id: request-id }
          {
            provider: tx-sender,
            patient: patient,
            data-type: data-type,
            purpose: purpose,
            requested-at: block-height,
            status: "pending",
            approved-by: none
          }
        )
        
        (var-set next-request-id (+ request-id u1))
        (log-access-attempt tx-sender patient data-type "request" true)
        
        (ok request-id)
      )
      ERR-NOT-FOUND
    )
  )
)

;; Approve access request
(define-public (approve-access-request (request-id uint))
  (begin
    (asserts! (is-admin tx-sender) ERR-UNAUTHORIZED)
    
    (match (map-get? access-requests { request-id: request-id })
      request-data
      (begin
        (map-set access-requests
          { request-id: request-id }
          (merge request-data { 
            status: "approved",
            approved-by: (some tx-sender)
          })
        )
        (log-access-attempt (get provider request-data) (get patient request-data) (get data-type request-data) "approved" true)
        (ok true)
      )
      ERR-NOT-FOUND
    )
  )
)

;; Activate emergency access
(define-public (activate-emergency-access (patient principal) (reason (string-ascii 200)))
  (let (
    (expires-at (+ block-height u144)) ;; Emergency access for 24 hours (144 blocks)
  )
    (asserts! (is-provider-verified tx-sender) ERR-UNAUTHORIZED)
    
    (match (map-get? healthcare-providers { provider: tx-sender })
      provider-data
      (begin
        (asserts! (is-eq (get role provider-data) ROLE-EMERGENCY) ERR-INSUFFICIENT-PERMISSIONS)
        
        (map-set emergency-access
          { provider: tx-sender, patient: patient }
          {
            activated-at: block-height,
            expires-at: expires-at,
            reason: reason,
            active: true
          }
        )
        
        (log-access-attempt tx-sender patient "emergency-info" "emergency-access" true)
        (ok true)
      )
      ERR-NOT-FOUND
    )
  )
)

;; Deactivate provider
(define-public (deactivate-provider (provider principal))
  (begin
    (asserts! (is-admin tx-sender) ERR-UNAUTHORIZED)
    
    (match (map-get? healthcare-providers { provider: provider })
      provider-data
      (begin
        (map-set healthcare-providers
          { provider: provider }
          (merge provider-data { active: false })
        )
        (ok true)
      )
      ERR-NOT-FOUND
    )
  )
)

;; Update contract owner
(define-public (transfer-ownership (new-owner principal))
  (begin
    (asserts! (is-eq tx-sender (var-get contract-owner)) ERR-UNAUTHORIZED)
    (var-set contract-owner new-owner)
    (ok true)
  )
)

;; Read-only functions

;; Get provider information
(define-read-only (get-provider-info (provider principal))
  (map-get? healthcare-providers { provider: provider })
)

;; Check if provider has access to specific data type
(define-read-only (check-access-permission (provider principal) (data-type (string-ascii 50)))
  (match (map-get? healthcare-providers { provider: provider })
    provider-data
    (and 
      (get verified provider-data)
      (get active provider-data)
      (can-access-data-type (get role provider-data) data-type)
    )
    false
  )
)

;; Get access request details
(define-read-only (get-access-request (request-id uint))
  (map-get? access-requests { request-id: request-id })
)

;; Get access log entry
(define-read-only (get-access-log (log-id uint))
  (map-get? access-logs { log-id: log-id })
)

;; Check emergency access status
(define-read-only (check-emergency-access (provider principal) (patient principal))
  (match (map-get? emergency-access { provider: provider, patient: patient })
    emergency-data
    (and 
      (get active emergency-data)
      (< block-height (get expires-at emergency-data))
    )
    false
  )
)

;; Get contract owner
(define-read-only (get-contract-owner)
  (var-get contract-owner)
)

;; Verify if principal is verified provider
(define-read-only (is-verified-provider (provider principal))
  (is-provider-verified provider)
)

;; Get role name as string
(define-read-only (get-role-name (role uint))
  (if (is-eq role ROLE-ADMIN) "admin"
    (if (is-eq role ROLE-DOCTOR) "doctor"
      (if (is-eq role ROLE-NURSE) "nurse"
        (if (is-eq role ROLE-TECHNICIAN) "technician"
          (if (is-eq role ROLE-RESEARCHER) "researcher"
            (if (is-eq role ROLE-EMERGENCY) "emergency"
              "unknown"
            )
          )
        )
      )
    )
  )
)
