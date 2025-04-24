;; AI Compute Resources Tokenization Protocol - Version 2
;; Enhanced with resource management and allocation features

;; Constants
(define-constant ERR-NOT-ADMINISTRATOR (err u1))
(define-constant ERR-NETWORK-OFFLINE (err u2))
(define-constant ERR-INVALID-RESOURCE (err u3))
(define-constant ERR-RESOURCE-ALLOCATED (err u4))
(define-constant ERR-INVALID-PARAMETER (err u5))
(define-constant ERR-INSUFFICIENT-COMPUTE (err u6))
(define-constant ERR-RESOURCE-EXISTS (err u7))
(define-constant MAX-RESOURCE-ID u500) ;; Maximum allowed resource ID

;; Data Variables
(define-data-var network-administrator principal tx-sender)
(define-data-var network-online bool false)
(define-data-var compute-cycle uint u0)
(define-data-var minimum-compute-units uint u1000000) ;; 1 million compute units minimum
(define-data-var energy-credits uint u0)

;; Resource Allocation Structure
(define-map compute-resources
    uint
    {
        model-name: (string-utf8 128),
        specifications: (string-utf8 512),
        resource-signature: (buff 32),    ;; SHA256 hash of the resource verification
        usage-confirmed: uint,
        usage-rejected: uint,
        total-available-compute: uint,     ;; Total compute units available for this resource
        allocated: bool
    }
)

;; Researcher Profiles
(define-map researcher-profiles
    principal
    {
        compute-balance: uint,
        resources-used: (list 20 uint),
        priority-level: uint           ;; Can be different from compute balance (premium tier)
    }
)

;; Allocation Records
(define-map allocation-records
    {resource-id: uint, researcher: principal}
    {
        compute-allocated: uint
    }
)

;; Authorization
(define-private (is-administrator)
    (is-eq tx-sender (var-get network-administrator)))

;; Network Management Functions
(define-public (activate-network)
    (begin
        (asserts! (is-administrator) ERR-NOT-ADMINISTRATOR)
        (var-set network-online true)
        (var-set compute-cycle u0)
        (var-set energy-credits u0)
        (ok true)))

(define-public (register-resource
    (resource-id uint)
    (model-name (string-utf8 128))
    (specifications (string-utf8 512))
    (resource-signature (buff 32)))
    (let (
        (researcher-profile (unwrap! (map-get? researcher-profiles tx-sender) ERR-INSUFFICIENT-COMPUTE))
        (total-compute-capacity u10000000) ;; Example: 10M compute units
        )
        
        ;; Check network status
        (asserts! (var-get network-online) ERR-NETWORK-OFFLINE)
        
        ;; Validate resource-id is within acceptable range
        (asserts! (<= resource-id MAX-RESOURCE-ID) ERR-INVALID-PARAMETER)
        
        ;; Check if resource already exists
        (asserts! (is-none (map-get? compute-resources resource-id)) ERR-RESOURCE-EXISTS)
        
        ;; Validate model-name and specifications are not empty
        (asserts! (> (len model-name) u0) ERR-INVALID-PARAMETER)
        (asserts! (> (len specifications) u0) ERR-INVALID-PARAMETER)
        
        ;; Check researcher has enough compute to register resource
        (asserts! (>= (get compute-balance researcher-profile) (var-get minimum-compute-units)) ERR-INSUFFICIENT-COMPUTE)
        
        ;; Set the resource data
        (map-set compute-resources resource-id
            {
                model-name: model-name,
                specifications: specifications,
                resource-signature: resource-signature,
                usage-confirmed: u0,
                usage-rejected: u0,
                total-available-compute: total-compute-capacity,
                allocated: false
            })
        
        ;; Update researcher profile
        (map-set researcher-profiles tx-sender
            (merge researcher-profile {
                resources-used: (unwrap! (as-max-len? 
                    (append (get resources-used researcher-profile) resource-id) u20)
                    ERR-INVALID-PARAMETER)
            }))
        
        (ok true)))

;; Research Registration Functions
(define-public (register-researcher (compute-amount uint))
    (begin
        (asserts! (var-get network-online) ERR-NETWORK-OFFLINE)
        ;; Require minimum compute amount
        (asserts! (>= compute-amount (var-get minimum-compute-units)) ERR-INSUFFICIENT-COMPUTE)
        
        ;; Transfer tokens to network energy credits
        (try! (stx-transfer? compute-amount tx-sender (var-get network-administrator)))
        
        ;; Initialize researcher profile
        (map-set researcher-profiles tx-sender
            {
                compute-balance: compute-amount,
                resources-used: (list),
                priority-level: compute-amount
            })
            
        ;; Update energy credits
        (var-set energy-credits (+ (var-get energy-credits) compute-amount))
        
        (ok true)))

;; Allocation Functions
(define-public (allocate-compute
    (resource-id uint)
    (vote-confirmed bool))
    (let (
        (resource (unwrap! (map-get? compute-resources resource-id) ERR-INVALID-RESOURCE))
        (researcher (unwrap! (map-get? researcher-profiles tx-sender) ERR-INSUFFICIENT-COMPUTE))
        (priority-level (get priority-level researcher))
        )
        
        ;; Check network status
        (asserts! (var-get network-online) ERR-NETWORK-OFFLINE)
        
        ;; Check resource hasn't been allocated
        (asserts! (not (get allocated resource)) ERR-RESOURCE-ALLOCATED)
        
        ;; Record allocation
        (map-set allocation-records 
            {resource-id: resource-id, researcher: tx-sender}
            {
                compute-allocated: priority-level
            })
        
        ;; Update usage counts
        (if vote-confirmed
            (map-set compute-resources resource-id
                (merge resource {usage-confirmed: (+ (get usage-confirmed resource) priority-level)}))
            (map-set compute-resources resource-id
                (merge resource {usage-rejected: (+ (get usage-rejected resource) priority-level)}))
        )
        
        (ok true)))

;; Resource Finalization
(define-public (finalize-resource (resource-id uint))
    (let (
        (resource (unwrap! (map-get? compute-resources resource-id) ERR-INVALID-RESOURCE))
        )
        
        ;; Check network status
        (asserts! (var-get network-online) ERR-NETWORK-OFFLINE)
        
        ;; Only administrator can finalize resources
        (asserts! (is-administrator) ERR-NOT-ADMINISTRATOR)
        
        ;; Check resource hasn't been allocated
        (asserts! (not (get allocated resource)) ERR-RESOURCE-ALLOCATED)
        
        ;; Update resource status
        (map-set compute-resources resource-id
            (merge resource {
                allocated: true
            }))
        
        (ok true)))

;; Read-only functions
(define-read-only (get-resource-details (resource-id uint))
    (map-get? compute-resources resource-id))

(define-read-only (get-researcher-profile (researcher principal))
    (map-get? researcher-profiles researcher))

(define-read-only (get-network-metrics)
    {
        online: (var-get network-online),
        compute-cycle: (var-get compute-cycle),
        energy-credits: (var-get energy-credits),
        minimum-compute-units: (var-get minimum-compute-units)
    })

(define-public (update-minimum-compute (new-minimum uint))
    (begin
        (asserts! (is-administrator) ERR-NOT-ADMINISTRATOR)
        (var-set minimum-compute-units new-minimum)
        (ok true)))

(define-public (shutdown-network)
    (begin
        (asserts! (is-administrator) ERR-NOT-ADMINISTRATOR)
        (var-set network-online false)
        (ok true)))

(define-public (advance-compute-cycle)
    (begin
        (asserts! (is-administrator) ERR-NOT-ADMINISTRATOR)
        (asserts! (var-get network-online) ERR-NETWORK-OFFLINE)
        (var-set compute-cycle (+ (var-get compute-cycle) u1))
        (ok true)))

(define-public (transfer-administrator-role (new-administrator principal))
    (begin
        (asserts! (is-administrator) ERR-NOT-ADMINISTRATOR)
        (var-set network-administrator new-administrator)
        (ok true)))