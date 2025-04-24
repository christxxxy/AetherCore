;; AI Compute Resources Tokenization Protocol - Version 1
;; Basic framework with core functionality

;; Constants
(define-constant ERR-NOT-ADMINISTRATOR (err u1))
(define-constant ERR-NETWORK-OFFLINE (err u2))
(define-constant ERR-INVALID-RESOURCE (err u3))
(define-constant ERR-INSUFFICIENT-COMPUTE (err u6))

;; Data Variables
(define-data-var network-administrator principal tx-sender)
(define-data-var network-online bool false)
(define-data-var compute-cycle uint u0)
(define-data-var minimum-compute-units uint u1000000) ;; 1 million compute units minimum

;; Resource Structure
(define-map compute-resources
    uint
    {
        model-name: (string-utf8 128),
        specifications: (string-utf8 512),
        total-available-compute: uint,     ;; Total compute units available for this resource
        allocated: bool
    }
)

;; Researcher Profiles
(define-map researcher-profiles
    principal
    {
        compute-balance: uint,
        resources-used: (list 10 uint)
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
        (ok true)))

(define-public (register-resource
    (resource-id uint)
    (model-name (string-utf8 128))
    (specifications (string-utf8 512)))
    (let (
        (researcher-profile (unwrap! (map-get? researcher-profiles tx-sender) ERR-INSUFFICIENT-COMPUTE))
        (total-compute-capacity u10000000) ;; Example: 10M compute units
        )
        
        ;; Check network status
        (asserts! (var-get network-online) ERR-NETWORK-OFFLINE)
                
        ;; Set the resource data
        (map-set compute-resources resource-id
            {
                model-name: model-name,
                specifications: specifications,
                total-available-compute: total-compute-capacity,
                allocated: false
            })
        
        ;; Update researcher profile
        (map-set researcher-profiles tx-sender
            (merge researcher-profile {
                resources-used: (unwrap! (as-max-len? 
                    (append (get resources-used researcher-profile) resource-id) u10)
                    ERR-INSUFFICIENT-COMPUTE)
            }))
        
        (ok true)))

;; Research Registration Functions
(define-public (register-researcher (compute-amount uint))
    (begin
        (asserts! (var-get network-online) ERR-NETWORK-OFFLINE)
        ;; Require minimum compute amount
        (asserts! (>= compute-amount (var-get minimum-compute-units)) ERR-INSUFFICIENT-COMPUTE)
        
        ;; Transfer tokens to network 
        (try! (stx-transfer? compute-amount tx-sender (var-get network-administrator)))
        
        ;; Initialize researcher profile
        (map-set researcher-profiles tx-sender
            {
                compute-balance: compute-amount,
                resources-used: (list)
            })
        
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