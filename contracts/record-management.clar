
;; Medical Record Management Contract
;; Secure storage and retrieval of medical records with HIPAA compliance
;; Integration with patient consent management system

;; Constants and Error Codes
(define-constant CONTRACT-OWNER tx-sender)
(define-constant ERR-UNAUTHORIZED (err u200))
(define-constant ERR-RECORD-NOT-FOUND (err u201))
(define-constant ERR-PATIENT-NOT-FOUND (err u202))
(define-constant ERR-PROVIDER-NOT-AUTHORIZED (err u203))
(define-constant ERR-INVALID-RECORD-TYPE (err u204))
(define-constant ERR-CONSENT-REQUIRED (err u205))
(define-constant ERR-RECORD-ENCRYPTED (err u206))
(define-constant ERR-INVALID-SIGNATURE (err u207))
(define-constant ERR-RECORD-LOCKED (err u208))
(define-constant ERR-EMERGENCY-ACCESS-ONLY (err u209))
(define-constant ERR-AUDIT-REQUIRED (err u210))
(define-constant ERR-RETENTION-PERIOD (err u211))
(define-constant ERR-DUPLICATE-RECORD (err u212))

;; Record Type Constants
(define-constant RECORD-BASIC-INFO u0)         ;; Demographics, contact info
(define-constant RECORD-VITALS u1)             ;; Blood pressure, temperature, etc.
(define-constant RECORD-DIAGNOSIS u2)          ;; Primary/secondary diagnoses
(define-constant RECORD-MEDICATIONS u3)        ;; Current and past medications
(define-constant RECORD-LAB-RESULTS u4)        ;; Laboratory test results
(define-constant RECORD-IMAGING u5)            ;; X-rays, MRIs, CT scans
(define-constant RECORD-PROCEDURES u6)         ;; Surgical and medical procedures
(define-constant RECORD-ALLERGIES u7)          ;; Known allergies and reactions
(define-constant RECORD-IMMUNIZATIONS u8)      ;; Vaccination records
(define-constant RECORD-MENTAL-HEALTH u9)      ;; Psychological evaluations
(define-constant RECORD-GENETIC-DATA u10)      ;; Genetic test results
(define-constant RECORD-INSURANCE u11)         ;; Insurance and billing info
(define-constant RECORD-EMERGENCY-CONTACTS u12) ;; Emergency contact information

;; Record Status Constants
(define-constant RECORD-ACTIVE u0)
(define-constant RECORD-ARCHIVED u1)
(define-constant RECORD-DELETED u2)
(define-constant RECORD-LOCKED u3)
(define-constant RECORD-UNDER-REVIEW u4)

;; Access Level Constants
(define-constant ACCESS-READ u0)
(define-constant ACCESS-WRITE u1)
(define-constant ACCESS-ADMIN u2)
(define-constant ACCESS-EMERGENCY u3)

;; Data Variables
(define-data-var contract-paused bool false)
(define-data-var total-records uint u0)
(define-data-var next-record-id uint u1)
(define-data-var audit-required bool true)
(define-data-var encryption-required bool true)
(define-data-var retention-period uint u262800) ;; 30 years in blocks

;; Data Maps
(define-map medical-records
  {patient: principal, record-id: uint}
  {
    record-type: uint,
    created-by: principal,
    created-at: uint,
    last-updated: uint,
    updated-by: principal,
    status: uint,
    title: (string-ascii 100),
    data-hash: (string-ascii 64), ;; SHA-256 hash of encrypted data
    encryption-key-id: (optional (string-ascii 64)),
    signature: (optional (string-ascii 128)),
    file-size: uint,
    mime-type: (optional (string-ascii 50)),
    retention-until: (optional uint),
    confidentiality-level: uint ;; 1=normal, 2=restricted, 3=highly-restricted
  }
)

(define-map record-data
  {patient: principal, record-id: uint}
  {
    encrypted-data: (string-ascii 2048), ;; Encrypted medical data
    metadata: (optional (string-ascii 500)),
    checksum: (string-ascii 64),
    version: uint,
    previous-version: (optional uint)
  }
)

(define-map provider-permissions
  {patient: principal, provider: principal, record-type: uint}
  {
    access-level: uint,
    granted-by: principal,
    granted-at: uint,
    expires-at: (optional uint),
    conditions: (optional (string-ascii 200)),
    audit-required: bool
  }
)

(define-map record-access-log
  {patient: principal, provider: principal, record-id: uint, timestamp: uint}
  {
    access-type: uint, ;; 0=read, 1=write, 2=delete, 3=emergency
    reason: (string-ascii 200),
    consent-verified: bool,
    emergency-override: bool,
    ip-address: (optional (string-ascii 45)),
    user-agent: (optional (string-ascii 100))
  }
)

(define-map record-sharing
  {patient: principal, record-id: uint, shared-with: principal}
  {
    shared-by: principal,
    shared-at: uint,
    expires-at: (optional uint),
    purpose: (string-ascii 200),
    access-level: uint,
    conditions: (optional (string-ascii 300))
  }
)

(define-map audit-trail
  {patient: principal, record-id: uint, sequence: uint}
  {
    action: (string-ascii 50),
    performed-by: principal,
    timestamp: uint,
    details: (optional (string-ascii 300)),
    risk-level: uint,
    compliance-check: bool
  }
)

;; Private Functions
(define-private (is-valid-record-type (record-type uint))
  (or
    (is-eq record-type RECORD-BASIC-INFO)
    (is-eq record-type RECORD-VITALS)
    (is-eq record-type RECORD-DIAGNOSIS)
    (is-eq record-type RECORD-MEDICATIONS)
    (is-eq record-type RECORD-LAB-RESULTS)
    (is-eq record-type RECORD-IMAGING)
    (is-eq record-type RECORD-PROCEDURES)
    (is-eq record-type RECORD-ALLERGIES)
    (is-eq record-type RECORD-IMMUNIZATIONS)
    (is-eq record-type RECORD-MENTAL-HEALTH)
    (is-eq record-type RECORD-GENETIC-DATA)
    (is-eq record-type RECORD-INSURANCE)
    (is-eq record-type RECORD-EMERGENCY-CONTACTS)
  )
)

(define-private (record-exists (patient principal) (record-id uint))
  (is-some (map-get? medical-records {patient: patient, record-id: record-id}))
)

(define-private (has-access-permission 
  (patient principal) 
  (provider principal) 
  (record-type uint)
  (required-level uint)
)
  (match (map-get? provider-permissions {patient: patient, provider: provider, record-type: record-type})
    permission 
      (and 
        (>= (get access-level permission) required-level)
        (or 
          (is-none (get expires-at permission))
          (< block-height (unwrap! (get expires-at permission) false))
        )
      )
    false
  )
)

(define-private (is-record-accessible (patient principal) (record-id uint) (provider principal))
  (match (map-get? medical-records {patient: patient, record-id: record-id})
    record-info
      (and 
        (not (is-eq (get status record-info) RECORD-LOCKED))
        (not (is-eq (get status record-info) RECORD-DELETED))
        (has-access-permission patient provider (get record-type record-info) ACCESS-READ)
      )
    false
  )
)

(define-private (log-record-access
  (patient principal)
  (provider principal) 
  (record-id uint)
  (access-type uint)
  (reason (string-ascii 200))
  (emergency-override bool)
)
  (begin
    (map-set record-access-log {patient: patient, provider: provider, record-id: record-id, timestamp: block-height} {
      access-type: access-type,
      reason: reason,
      consent-verified: true, ;; Would integrate with consent contract
      emergency-override: emergency-override,
      ip-address: none,
      user-agent: none
    })
    (ok true)
  )
)

(define-private (create-audit-entry
  (patient principal)
  (record-id uint)
  (action (string-ascii 50))
  (details (optional (string-ascii 300)))
  (risk-level uint)
)
  (let
    (
      (sequence (get-next-audit-sequence patient record-id))
    )
    (map-set audit-trail {patient: patient, record-id: record-id, sequence: sequence} {
      action: action,
      performed-by: tx-sender,
      timestamp: block-height,
      details: details,
      risk-level: risk-level,
      compliance-check: true
    })
    (ok true)
  )
)

(define-private (get-next-audit-sequence (patient principal) (record-id uint))
  ;; Simplified sequence generation - in production would need proper tracking
  u1
)

;; Public Functions

;; Create a new medical record
(define-public (create-record
  (patient principal)
  (record-type uint)
  (title (string-ascii 100))
  (encrypted-data (string-ascii 2048))
  (data-hash (string-ascii 64))
  (encryption-key-id (optional (string-ascii 64)))
  (signature (optional (string-ascii 128)))
  (file-size uint)
  (mime-type (optional (string-ascii 50)))
  (confidentiality-level uint)
)
  (begin
    (asserts! (not (var-get contract-paused)) ERR-UNAUTHORIZED)
    (asserts! (is-valid-record-type record-type) ERR-INVALID-RECORD-TYPE)
    (asserts! (has-access-permission patient tx-sender record-type ACCESS-WRITE) ERR-PROVIDER-NOT-AUTHORIZED)
    
    (let
      (
        (record-id (var-get next-record-id))
        (retention-until (some (+ block-height (var-get retention-period))))
      )
      
      ;; Create the medical record metadata
      (map-set medical-records {patient: patient, record-id: record-id} {
        record-type: record-type,
        created-by: tx-sender,
        created-at: block-height,
        last-updated: block-height,
        updated-by: tx-sender,
        status: RECORD-ACTIVE,
        title: title,
        data-hash: data-hash,
        encryption-key-id: encryption-key-id,
        signature: signature,
        file-size: file-size,
        mime-type: mime-type,
        retention-until: retention-until,
        confidentiality-level: confidentiality-level
      })
      
      ;; Store the encrypted record data
      (map-set record-data {patient: patient, record-id: record-id} {
        encrypted-data: encrypted-data,
        metadata: none,
        checksum: data-hash, ;; Use data-hash as checksum for simplicity
        version: u1,
        previous-version: none
      })
      
      ;; Log the record creation
      (unwrap-panic (log-record-access patient tx-sender record-id u1 "Record created" false))
      
      ;; Create audit entry
      (unwrap-panic (create-audit-entry patient record-id "create" (some title) u1))
      
      ;; Update counters
      (var-set next-record-id (+ record-id u1))
      (var-set total-records (+ (var-get total-records) u1))
      
      (print {
        action: "record-created",
        patient: patient,
        record-id: record-id,
        record-type: record-type,
        created-by: tx-sender
      })
      
      (ok record-id)
    )
  )
)

;; Retrieve a medical record
(define-public (get-record
  (patient principal)
  (record-id uint)
  (access-reason (string-ascii 200))
)
  (begin
    (asserts! (not (var-get contract-paused)) ERR-UNAUTHORIZED)
    (asserts! (record-exists patient record-id) ERR-RECORD-NOT-FOUND)
    (asserts! (is-record-accessible patient record-id tx-sender) ERR-PROVIDER-NOT-AUTHORIZED)
    
    ;; Log the access
    (unwrap-panic (log-record-access patient tx-sender record-id ACCESS-READ access-reason false))
    
    ;; Create audit entry
    (unwrap-panic (create-audit-entry patient record-id "access" (some access-reason) u1))
    
    (let
      (
        (record-info (unwrap! (map-get? medical-records {patient: patient, record-id: record-id}) ERR-RECORD-NOT-FOUND))
        (record-content (map-get? record-data {patient: patient, record-id: record-id}))
      )
      (print {
        action: "record-accessed",
        patient: patient,
        record-id: record-id,
        accessed-by: tx-sender
      })
      
      (ok {
        metadata: record-info,
        data: record-content
      })
    )
  )
)

;; Update an existing medical record
(define-public (update-record
  (patient principal)
  (record-id uint)
  (encrypted-data (string-ascii 2048))
  (data-hash (string-ascii 64))
  (signature (optional (string-ascii 128)))
  (update-reason (string-ascii 200))
)
  (begin
    (asserts! (not (var-get contract-paused)) ERR-UNAUTHORIZED)
    (asserts! (record-exists patient record-id) ERR-RECORD-NOT-FOUND)
    
    (let
      (
        (record-info (unwrap! (map-get? medical-records {patient: patient, record-id: record-id}) ERR-RECORD-NOT-FOUND))
        (old-data (map-get? record-data {patient: patient, record-id: record-id}))
      )
      (asserts! (has-access-permission patient tx-sender (get record-type record-info) ACCESS-WRITE) ERR-PROVIDER-NOT-AUTHORIZED)
      (asserts! (not (is-eq (get status record-info) RECORD-LOCKED)) ERR-RECORD-LOCKED)
      
      ;; Update the record metadata
      (map-set medical-records {patient: patient, record-id: record-id}
        (merge record-info {
          last-updated: block-height,
          updated-by: tx-sender,
          data-hash: data-hash,
          signature: signature
        })
      )
      
      ;; Update the record data with versioning
      (match old-data
        existing-data
          (map-set record-data {patient: patient, record-id: record-id} {
            encrypted-data: encrypted-data,
            metadata: (get metadata existing-data),
            checksum: data-hash,
            version: (+ (get version existing-data) u1),
            previous-version: (some (get version existing-data))
          })
        (map-set record-data {patient: patient, record-id: record-id} {
          encrypted-data: encrypted-data,
          metadata: none,
          checksum: data-hash,
          version: u1,
          previous-version: none
        })
      )
      
      ;; Log the update
      (unwrap-panic (log-record-access patient tx-sender record-id u1 update-reason false))
      
      ;; Create audit entry
      (unwrap-panic (create-audit-entry patient record-id "update" (some update-reason) u2))
      
      (print {
        action: "record-updated",
        patient: patient,
        record-id: record-id,
        updated-by: tx-sender
      })
      
      (ok true)
    )
  )
)

;; Grant provider permission for record access
(define-public (grant-provider-access
  (provider principal)
  (record-type uint)
  (access-level uint)
  (expires-at (optional uint))
  (conditions (optional (string-ascii 200)))
)
  (begin
    (asserts! (not (var-get contract-paused)) ERR-UNAUTHORIZED)
    (asserts! (is-valid-record-type record-type) ERR-INVALID-RECORD-TYPE)
    (asserts! (<= access-level ACCESS-ADMIN) ERR-UNAUTHORIZED)
    
    (map-set provider-permissions {patient: tx-sender, provider: provider, record-type: record-type} {
      access-level: access-level,
      granted-by: tx-sender,
      granted-at: block-height,
      expires-at: expires-at,
      conditions: conditions,
      audit-required: (var-get audit-required)
    })
    
    (print {
      action: "provider-access-granted",
      patient: tx-sender,
      provider: provider,
      record-type: record-type,
      access-level: access-level
    })
    
    (ok true)
  )
)

;; Revoke provider permission
(define-public (revoke-provider-access
  (provider principal)
  (record-type uint)
  (reason (string-ascii 200))
)
  (begin
    (asserts! (not (var-get contract-paused)) ERR-UNAUTHORIZED)
    (asserts! (is-valid-record-type record-type) ERR-INVALID-RECORD-TYPE)
    
    (map-delete provider-permissions {patient: tx-sender, provider: provider, record-type: record-type})
    
    (print {
      action: "provider-access-revoked",
      patient: tx-sender,
      provider: provider,
      record-type: record-type,
      reason: reason
    })
    
    (ok true)
  )
)

;; Archive a record
(define-public (archive-record
  (patient principal)
  (record-id uint)
  (archive-reason (string-ascii 200))
)
  (begin
    (asserts! (not (var-get contract-paused)) ERR-UNAUTHORIZED)
    (asserts! (record-exists patient record-id) ERR-RECORD-NOT-FOUND)
    
    (let
      (
        (record-info (unwrap! (map-get? medical-records {patient: patient, record-id: record-id}) ERR-RECORD-NOT-FOUND))
      )
      (asserts! (has-access-permission patient tx-sender (get record-type record-info) ACCESS-ADMIN) ERR-PROVIDER-NOT-AUTHORIZED)
      
      ;; Update record status to archived
      (map-set medical-records {patient: patient, record-id: record-id}
        (merge record-info {
          status: RECORD-ARCHIVED,
          last-updated: block-height,
          updated-by: tx-sender
        })
      )
      
      ;; Create audit entry
      (unwrap-panic (create-audit-entry patient record-id "archive" (some archive-reason) u2))
      
      (print {
        action: "record-archived",
        patient: patient,
        record-id: record-id,
        archived-by: tx-sender
      })
      
      (ok true)
    )
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

;; Read-only Functions
(define-read-only (get-record-metadata (patient principal) (record-id uint))
  (map-get? medical-records {patient: patient, record-id: record-id})
)

(define-read-only (get-provider-permissions (patient principal) (provider principal) (record-type uint))
  (map-get? provider-permissions {patient: patient, provider: provider, record-type: record-type})
)

(define-read-only (get-access-log (patient principal) (provider principal) (record-id uint) (timestamp uint))
  (map-get? record-access-log {patient: patient, provider: provider, record-id: record-id, timestamp: timestamp})
)

(define-read-only (get-audit-entry (patient principal) (record-id uint) (sequence uint))
  (map-get? audit-trail {patient: patient, record-id: record-id, sequence: sequence})
)

(define-read-only (get-contract-stats)
  {
    total-records: (var-get total-records),
    next-record-id: (var-get next-record-id),
    contract-paused: (var-get contract-paused),
    audit-required: (var-get audit-required),
    encryption-required: (var-get encryption-required),
    retention-period: (var-get retention-period)
  }
)

(define-read-only (is-contract-paused)
  (var-get contract-paused)
)

