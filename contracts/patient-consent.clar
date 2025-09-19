;; Patient Consent Contract
;; Patient consent management for secure medical data sharing
;; HIPAA-compliant consent tracking and management system

;; Constants and Error Codes
(define-constant CONTRACT-OWNER tx-sender)
(define-constant ERR-UNAUTHORIZED (err u100))
(define-constant ERR-PATIENT-NOT-FOUND (err u101))
(define-constant ERR-PROVIDER-NOT-FOUND (err u102))
(define-constant ERR-CONSENT-NOT-FOUND (err u103))
(define-constant ERR-CONSENT-EXPIRED (err u104))
(define-constant ERR-INVALID-DATA-TYPE (err u105))
(define-constant ERR-EMERGENCY-ONLY (err u106))
(define-constant ERR-CONSENT-REVOKED (err u107))
(define-constant ERR-INVALID-DURATION (err u108))
(define-constant ERR-INSUFFICIENT-PERMISSIONS (err u109))
(define-constant ERR-PATIENT-DECEASED (err u110))

;; Data Type Constants
(define-constant DATA-BASIC-INFO u0)        ;; Name, contact, demographics
(define-constant DATA-MEDICAL-HISTORY u1)   ;; Past diagnoses, procedures
(define-constant DATA-LAB-RESULTS u2)       ;; Test results, imaging
(define-constant DATA-TREATMENT-PLANS u3)   ;; Current medications, care plans
(define-constant DATA-MENTAL-HEALTH u4)     ;; Psychological data (special protection)
(define-constant DATA-GENETIC-INFO u5)      ;; Genetic testing (enhanced protection)
(define-constant DATA-FINANCIAL u6)         ;; Billing and insurance information
(define-constant DATA-EMERGENCY u7)         ;; Emergency contact and medical alerts

;; Consent Status Constants
(define-constant CONSENT-ACTIVE u0)
(define-constant CONSENT-EXPIRED u1)
(define-constant CONSENT-REVOKED u2)
(define-constant CONSENT-SUSPENDED u3)

;; Emergency Override Levels
(define-constant EMERGENCY-LEVEL-CRITICAL u0)  ;; Life-threatening
(define-constant EMERGENCY-LEVEL-URGENT u1)    ;; Urgent care needed
(define-constant EMERGENCY-LEVEL-STANDARD u2)  ;; Standard emergency

;; Data Variables
(define-data-var contract-paused bool false)
(define-data-var total-patients uint u0)
(define-data-var total-consents uint u0)
(define-data-var emergency-override-timeout uint u72) ;; 72 hours in blocks

;; Data Maps
(define-map patient-profiles
  principal ;; patient address
  {
    patient-id: (string-ascii 64),
    date-of-birth: uint,
    emergency-contact: (optional principal),
    primary-physician: (optional principal),
    deceased: bool,
    registration-date: uint,
    last-updated: uint
  }
)

(define-map consent-grants
  {patient: principal, provider: principal, data-type: uint}
  {
    granted-at: uint,
    expires-at: (optional uint),
    status: uint,
    purpose: (string-ascii 200),
    restrictions: (optional (string-ascii 300)),
    consent-id: (string-ascii 64)
  }
)

(define-map consent-history
  {patient: principal, consent-id: (string-ascii 64), sequence: uint}
  {
    action: (string-ascii 20), ;; "granted", "revoked", "expired", "suspended"
    provider: principal,
    timestamp: uint,
    reason: (optional (string-ascii 200)),
    initiated-by: principal
  }
)

(define-map emergency-overrides
  {patient: principal, provider: principal, timestamp: uint}
  {
    override-level: uint,
    reason: (string-ascii 300),
    authorized-by: principal,
    expires-at: uint,
    patient-notified: bool
  }
)

(define-map patient-preferences
  principal ;; patient
  {
    emergency-override-allowed: bool,
    research-participation: bool,
    data-sharing-level: uint, ;; 0=minimal, 1=standard, 2=full
    notification-preferences: uint,
    auto-expire-duration: (optional uint)
  }
)

;; Private Functions
(define-private (is-valid-data-type (data-type uint))
  (or
    (is-eq data-type DATA-BASIC-INFO)
    (is-eq data-type DATA-MEDICAL-HISTORY)
    (is-eq data-type DATA-LAB-RESULTS)
    (is-eq data-type DATA-TREATMENT-PLANS)
    (is-eq data-type DATA-MENTAL-HEALTH)
    (is-eq data-type DATA-GENETIC-INFO)
    (is-eq data-type DATA-FINANCIAL)
    (is-eq data-type DATA-EMERGENCY)
  )
)

(define-private (patient-exists (patient principal))
  (is-some (map-get? patient-profiles patient))
)

(define-private (is-consent-active (patient principal) (provider principal) (data-type uint))
  (match (map-get? consent-grants {patient: patient, provider: provider, data-type: data-type})
    consent-data 
      (and 
        (is-eq (get status consent-data) CONSENT-ACTIVE)
        (or 
          (is-none (get expires-at consent-data))
          (< block-height (unwrap! (get expires-at consent-data) false))
        )
      )
    false
  )
)

(define-private (patient-deceased (patient principal))
  (match (map-get? patient-profiles patient)
    profile (get deceased profile)
    false
  )
)

(define-private (is-emergency-situation (override-level uint))
  (or
    (is-eq override-level EMERGENCY-LEVEL-CRITICAL)
    (is-eq override-level EMERGENCY-LEVEL-URGENT)
    (is-eq override-level EMERGENCY-LEVEL-STANDARD)
  )
)

;; Public Functions

;; Register a patient profile
(define-public (register-patient
  (patient-id (string-ascii 64))
  (date-of-birth uint)
  (emergency-contact (optional principal))
  (primary-physician (optional principal))
)
  (begin
    (asserts! (not (var-get contract-paused)) ERR-UNAUTHORIZED)
    (asserts! (is-none (map-get? patient-profiles tx-sender)) ERR-UNAUTHORIZED)
    
    (map-set patient-profiles tx-sender {
      patient-id: patient-id,
      date-of-birth: date-of-birth,
      emergency-contact: emergency-contact,
      primary-physician: primary-physician,
      deceased: false,
      registration-date: block-height,
      last-updated: block-height
    })
    
    ;; Set default patient preferences
    (map-set patient-preferences tx-sender {
      emergency-override-allowed: true,
      research-participation: false,
      data-sharing-level: u1, ;; standard
      notification-preferences: u1,
      auto-expire-duration: (some u8760) ;; 1 year in blocks
    })
    
    (var-set total-patients (+ (var-get total-patients) u1))
    
    (print {
      action: "patient-registered",
      patient: tx-sender,
      patient-id: patient-id
    })
    (ok true)
  )
)

;; Grant consent for specific data type
(define-public (grant-consent
  (provider principal)
  (data-type uint)
  (expires-at (optional uint))
  (purpose (string-ascii 200))
  (restrictions (optional (string-ascii 300)))
  (consent-id (string-ascii 64))
)
  (begin
    (asserts! (not (var-get contract-paused)) ERR-UNAUTHORIZED)
    (asserts! (patient-exists tx-sender) ERR-PATIENT-NOT-FOUND)
    (asserts! (not (patient-deceased tx-sender)) ERR-PATIENT-DECEASED)
    (asserts! (is-valid-data-type data-type) ERR-INVALID-DATA-TYPE)
    
    ;; Grant consent for the data type
    (map-set consent-grants {patient: tx-sender, provider: provider, data-type: data-type} {
      granted-at: block-height,
      expires-at: expires-at,
      status: CONSENT-ACTIVE,
      purpose: purpose,
      restrictions: restrictions,
      consent-id: consent-id
    })
    
    ;; Record consent action in history
    (map-set consent-history {patient: tx-sender, consent-id: consent-id, sequence: u1} {
      action: "granted",
      provider: provider,
      timestamp: block-height,
      reason: (some purpose),
      initiated-by: tx-sender
    })
    
    (var-set total-consents (+ (var-get total-consents) u1))
    
    (print {
      action: "consent-granted",
      patient: tx-sender,
      provider: provider,
      data-type: data-type,
      consent-id: consent-id
    })
    (ok true)
  )
)

;; Revoke consent for specific data type
(define-public (revoke-consent
  (provider principal)
  (data-type uint)
  (reason (optional (string-ascii 200)))
  (consent-id (string-ascii 64))
)
  (begin
    (asserts! (not (var-get contract-paused)) ERR-UNAUTHORIZED)
    (asserts! (patient-exists tx-sender) ERR-PATIENT-NOT-FOUND)
    (asserts! (is-valid-data-type data-type) ERR-INVALID-DATA-TYPE)
    
    ;; Revoke consent for the data type
    (match (map-get? consent-grants {patient: tx-sender, provider: provider, data-type: data-type})
      consent-data (begin
        (map-set consent-grants {patient: tx-sender, provider: provider, data-type: data-type}
          (merge consent-data {status: CONSENT-REVOKED}))
        
        ;; Record revocation in history
        (map-set consent-history {patient: tx-sender, consent-id: consent-id, sequence: u2} {
          action: "revoked",
          provider: provider,
          timestamp: block-height,
          reason: reason,
          initiated-by: tx-sender
        })
        
        (print {
          action: "consent-revoked",
          patient: tx-sender,
          provider: provider,
          data-type: data-type,
          consent-id: consent-id
        })
        (ok true)
      )
      ERR-CONSENT-NOT-FOUND
    )
  )
)

;; Emergency override for critical care
(define-public (emergency-override
  (patient principal)
  (data-type uint)
  (override-level uint)
  (reason (string-ascii 300))
)
  (begin
    (asserts! (not (var-get contract-paused)) ERR-UNAUTHORIZED)
    (asserts! (patient-exists patient) ERR-PATIENT-NOT-FOUND)
    (asserts! (is-emergency-situation override-level) ERR-EMERGENCY-ONLY)
    (asserts! (is-valid-data-type data-type) ERR-INVALID-DATA-TYPE)
    
    ;; Check patient preferences for emergency override
    (let
      (
        (preferences (default-to 
          {emergency-override-allowed: true, research-participation: false, 
           data-sharing-level: u1, notification-preferences: u1, 
           auto-expire-duration: none}
          (map-get? patient-preferences patient)))
        (expires-at (+ block-height (var-get emergency-override-timeout)))
      )
      (asserts! (get emergency-override-allowed preferences) ERR-INSUFFICIENT-PERMISSIONS)
      
      ;; Record emergency override
      (map-set emergency-overrides {patient: patient, provider: tx-sender, timestamp: block-height} {
        override-level: override-level,
        reason: reason,
        authorized-by: tx-sender,
        expires-at: expires-at,
        patient-notified: false
      })
      
      (print {
        action: "emergency-override",
        patient: patient,
        provider: tx-sender,
        override-level: override-level,
        data-type: data-type,
        expires-at: expires-at
      })
      (ok expires-at)
    )
  )
)

;; Update patient preferences
(define-public (update-patient-preferences
  (emergency-override-allowed bool)
  (research-participation bool)
  (data-sharing-level uint)
  (notification-preferences uint)
  (auto-expire-duration (optional uint))
)
  (begin
    (asserts! (not (var-get contract-paused)) ERR-UNAUTHORIZED)
    (asserts! (patient-exists tx-sender) ERR-PATIENT-NOT-FOUND)
    
    (map-set patient-preferences tx-sender {
      emergency-override-allowed: emergency-override-allowed,
      research-participation: research-participation,
      data-sharing-level: data-sharing-level,
      notification-preferences: notification-preferences,
      auto-expire-duration: auto-expire-duration
    })
    
    (print {
      action: "preferences-updated",
      patient: tx-sender
    })
    (ok true)
  )
)

;; Administrative Functions
(define-public (pause-contract)
  (begin
    (asserts! (is-eq tx-sender CONTRACT-OWNER) ERR-UNAUTHORIZED)
    (var-set contract-paused true)
    (print {action: "contract-paused"})
    (ok true)
  )
)

(define-public (unpause-contract)
  (begin
    (asserts! (is-eq tx-sender CONTRACT-OWNER) ERR-UNAUTHORIZED)
    (var-set contract-paused false)
    (print {action: "contract-unpaused"})
    (ok true)
  )
)

(define-public (set-emergency-timeout (new-timeout uint))
  (begin
    (asserts! (is-eq tx-sender CONTRACT-OWNER) ERR-UNAUTHORIZED)
    (var-set emergency-override-timeout new-timeout)
    (print {action: "timeout-updated", new-timeout: new-timeout})
    (ok true)
  )
)

;; Read-only Functions
(define-read-only (get-consent-status (patient principal) (provider principal) (data-type uint))
  (map-get? consent-grants {patient: patient, provider: provider, data-type: data-type})
)

(define-read-only (get-patient-profile (patient principal))
  (map-get? patient-profiles patient)
)

(define-read-only (get-patient-preferences (patient principal))
  (map-get? patient-preferences patient)
)

(define-read-only (check-consent-active (patient principal) (provider principal) (data-type uint))
  (is-consent-active patient provider data-type)
)

(define-read-only (get-emergency-override (patient principal) (provider principal) (timestamp uint))
  (map-get? emergency-overrides {patient: patient, provider: provider, timestamp: timestamp})
)

(define-read-only (get-consent-history (patient principal) (consent-id (string-ascii 64)) (sequence uint))
  (map-get? consent-history {patient: patient, consent-id: consent-id, sequence: sequence})
)

(define-read-only (get-contract-stats)
  {
    total-patients: (var-get total-patients),
    total-consents: (var-get total-consents),
    contract-paused: (var-get contract-paused),
    emergency-timeout: (var-get emergency-override-timeout)
  }
)

(define-read-only (is-patient-registered (patient principal))
  (patient-exists patient)
)

(define-read-only (is-contract-paused)
  (var-get contract-paused)
)


;; title: patient-consent
;; version:
;; summary:
;; description:

;; traits
;;

;; token definitions
;;

;; constants
;;

;; data vars
;;

;; data maps
;;

;; public functions
;;

;; read only functions
;;

;; private functions
;;

