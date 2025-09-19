;; title: patient-consent
;; Patient consent management for medical record sharing
;; Manages patient consent for data sharing with healthcare providers

;; Error codes
(define-constant ERR-UNAUTHORIZED (err u100))
(define-constant ERR-NOT-FOUND (err u101))
(define-constant ERR-ALREADY-EXISTS (err u102))
(define-constant ERR-EXPIRED (err u103))
(define-constant ERR-INVALID-DATA (err u104))

;; Data structures
(define-map patient-consents 
  { patient: principal, provider: principal, data-type: (string-ascii 50) }
  {
    granted-at: uint,
    expires-at: uint,
    purpose: (string-ascii 200),
    active: bool
  }
)

(define-map patient-registry
  { patient: principal }
  {
    registered-at: uint,
    total-consents: uint
  }
)

(define-map consent-history
  { patient: principal, sequence: uint }
  {
    provider: principal,
    data-type: (string-ascii 50),
    action: (string-ascii 20),
    timestamp: uint
  }
)

;; Storage for sequence numbers
(define-data-var next-consent-sequence uint u0)

;; Helper functions
(define-private (is-valid-data-type (data-type (string-ascii 50)))
  (or (is-eq data-type "medical-records")
      (is-eq data-type "lab-results")
      (is-eq data-type "prescriptions")
      (is-eq data-type "imaging")
      (is-eq data-type "emergency-info")
      (is-eq data-type "all"))
)

(define-private (is-consent-expired (expires-at uint))
  (> block-height expires-at)
)

(define-private (log-consent-action (patient principal) (provider principal) (data-type (string-ascii 50)) (action (string-ascii 20)))
  (let ((sequence (var-get next-consent-sequence)))
    (map-set consent-history
      { patient: patient, sequence: sequence }
      {
        provider: provider,
        data-type: data-type,
        action: action,
        timestamp: block-height
      }
    )
    (var-set next-consent-sequence (+ sequence u1))
    true
  )
)

;; Public functions

;; Register a patient in the system
(define-public (register-patient)
  (let ((patient tx-sender))
    (if (is-some (map-get? patient-registry { patient: patient }))
      ERR-ALREADY-EXISTS
      (begin
        (map-set patient-registry
          { patient: patient }
          {
            registered-at: block-height,
            total-consents: u0
          }
        )
        (ok true)
      )
    )
  )
)

;; Grant consent for data sharing
(define-public (grant-consent (provider principal) (data-type (string-ascii 50)) (duration uint) (purpose (string-ascii 200)))
  (let (
    (patient tx-sender)
    (expires-at (+ block-height duration))
    (consent-key { patient: patient, provider: provider, data-type: data-type })
  )
    (asserts! (is-valid-data-type data-type) ERR-INVALID-DATA)
    (asserts! (> duration u0) ERR-INVALID-DATA)
    (asserts! (is-some (map-get? patient-registry { patient: patient })) ERR-NOT-FOUND)
    
    (map-set patient-consents
      consent-key
      {
        granted-at: block-height,
        expires-at: expires-at,
        purpose: purpose,
        active: true
      }
    )
    
    ;; Update patient registry
    (match (map-get? patient-registry { patient: patient })
      registry-data
      (map-set patient-registry
        { patient: patient }
        (merge registry-data { total-consents: (+ (get total-consents registry-data) u1) })
      )
      false
    )
    
    ;; Log the action
    (log-consent-action patient provider data-type "granted")
    
    (ok true)
  )
)

;; Revoke consent
(define-public (revoke-consent (provider principal) (data-type (string-ascii 50)))
  (let (
    (patient tx-sender)
    (consent-key { patient: patient, provider: provider, data-type: data-type })
  )
    (match (map-get? patient-consents consent-key)
      consent-data
      (if (get active consent-data)
        (begin
          (map-set patient-consents
            consent-key
            (merge consent-data { active: false })
          )
          (log-consent-action patient provider data-type "revoked")
          (ok true)
        )
        ERR-NOT-FOUND
      )
      ERR-NOT-FOUND
    )
  )
)

;; Update consent purpose
(define-public (update-consent-purpose (provider principal) (data-type (string-ascii 50)) (new-purpose (string-ascii 200)))
  (let (
    (patient tx-sender)
    (consent-key { patient: patient, provider: provider, data-type: data-type })
  )
    (match (map-get? patient-consents consent-key)
      consent-data
      (if (and (get active consent-data) (not (is-consent-expired (get expires-at consent-data))))
        (begin
          (map-set patient-consents
            consent-key
            (merge consent-data { purpose: new-purpose })
          )
          (log-consent-action patient provider data-type "updated")
          (ok true)
        )
        ERR-EXPIRED
      )
      ERR-NOT-FOUND
    )
  )
)

;; Read-only functions

;; Check if consent is valid and active
(define-read-only (check-consent (patient principal) (provider principal) (data-type (string-ascii 50)))
  (match (map-get? patient-consents { patient: patient, provider: provider, data-type: data-type })
    consent-data
    (and 
      (get active consent-data)
      (not (is-consent-expired (get expires-at consent-data)))
    )
    false
  )
)

;; Get consent details
(define-read-only (get-consent-details (patient principal) (provider principal) (data-type (string-ascii 50)))
  (map-get? patient-consents { patient: patient, provider: provider, data-type: data-type })
)

;; Get patient registration info
(define-read-only (get-patient-info (patient principal))
  (map-get? patient-registry { patient: patient })
)

;; Get consent history for a patient
(define-read-only (get-consent-history (patient principal) (sequence uint))
  (map-get? consent-history { patient: patient, sequence: sequence })
)

;; Get all active consents for a patient (helper for UI)
(define-read-only (is-patient-registered (patient principal))
  (is-some (map-get? patient-registry { patient: patient }))
)

;; Check if data type is valid
(define-read-only (validate-data-type (data-type (string-ascii 50)))
  (is-valid-data-type data-type)
)
