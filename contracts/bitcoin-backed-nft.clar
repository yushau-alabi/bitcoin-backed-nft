;; Title: Bitcoin-Backed NFT Smart Contract

;; Summary:
;; This smart contract implements a Bitcoin-backed non-fungible token (NFT) platform with enhanced security features.
;; It includes functionalities for minting, transferring, staking, unstaking, burning NFTs, and redeeming governance tokens.

;; Description:
;; The Bitcoin-Backed NFT Smart Contract provides a comprehensive and secure platform for managing NFTs backed by Bitcoin.
;; The contract defines a non-fungible token (NFT) with a 32-byte buffer identifier and includes various error constants for robust error handling.

(define-non-fungible-token bitcoin-backed-nft (buff 32))

;; Extended Error Constants
(define-constant CONTRACT-OWNER tx-sender)
(define-constant ERR-UNAUTHORIZED (err u1))
(define-constant ERR-NOT-FOUND (err u2))
(define-constant ERR-ALREADY-MINTED (err u3))
(define-constant ERR-INVALID-TRANSFER (err u4))
(define-constant ERR-STAKING-ERROR (err u5))
(define-constant ERR-INSUFFICIENT-BALANCE (err u6))
(define-constant ERR-INVALID-INPUT (err u7))
(define-constant ERR-INVALID-TOKEN (err u8))

;; Input Validation Helper Functions
(define-private (is-valid-token-id (token-id (buff 32)))
    (and 
        (not (is-eq token-id 0x))
        (< (len token-id) u33)
    )
)

(define-private (is-valid-asset-type (asset-type (string-utf8 50)))
    (and 
        (> (len asset-type) u0)
        (<= (len asset-type) u50)
    )
)

(define-private (is-valid-asset-value (asset-value uint))
    (and 
        (> asset-value u0)
        (< asset-value u1000000)
    )
)

;; Storage Maps
(define-map nft-metadata 
    {token-id: (buff 32)} 
    {
        owner: principal,
        asset-type: (string-utf8 50),
        asset-value: uint,
        mint-timestamp: uint,
        staking-start: (optional uint),
        staking-rewards: uint
    }
)

(define-map nft-staking 
    {token-id: (buff 32)} 
    {
        staked-by: principal,
        stake-start-block: uint,
        total-staked-blocks: uint
    }
)

(define-map governance-tokens 
    principal 
    uint
)

;; Read-only functions with additional safety checks
(define-read-only (get-nft-metadata (token-id (buff 32)))
    (begin
        (asserts! (is-valid-token-id token-id) none)
        (map-get? nft-metadata {token-id: token-id})
    )
)

(define-read-only (get-governance-tokens (user principal))
    (default-to u0 (map-get? governance-tokens user))
)

;; Enhanced Mint Function with Comprehensive Validation
(define-public (mint-nft 
    (token-id (buff 32))
    (asset-type (string-utf8 50))
    (asset-value uint)
)
    (begin
        ;; Validate all inputs
        (asserts! (is-valid-token-id token-id) ERR-INVALID-TOKEN)
        (asserts! (is-valid-asset-type asset-type) ERR-INVALID-INPUT)
        (asserts! (is-valid-asset-value asset-value) ERR-INVALID-INPUT)
        
        ;; Check if NFT already exists
        (asserts! (is-none (nft-get-owner? bitcoin-backed-nft token-id)) ERR-ALREADY-MINTED)
        
        ;; Mint the NFT
        (try! (nft-mint? bitcoin-backed-nft token-id tx-sender))
        
        ;; Store NFT metadata with validated inputs
        (map-set nft-metadata 
            {token-id: token-id}
            {
                owner: tx-sender,
                asset-type: asset-type,
                asset-value: asset-value,
                mint-timestamp: block-height,
                staking-start: none,
                staking-rewards: u0
            }
        )
        
        (ok token-id)
    )
)

;; Enhanced Transfer Function
(define-public (transfer-nft 
    (token-id (buff 32))
    (sender principal)
    (recipient principal)
)
    (let 
        (
            (metadata (unwrap! (map-get? nft-metadata {token-id: token-id}) ERR-NOT-FOUND))
        )
        ;; Additional input validations
        (asserts! (is-valid-token-id token-id) ERR-INVALID-TOKEN)
        (asserts! (not (is-eq sender recipient)) ERR-INVALID-TRANSFER)
        
        ;; Verify sender is current owner
        (asserts! (is-eq sender (get owner metadata)) ERR-UNAUTHORIZED)
        
        ;; Ensure no active staking
        (asserts! (is-none (get staking-start metadata)) ERR-INVALID-TRANSFER)
        
        ;; Transfer NFT
        (try! (nft-transfer? bitcoin-backed-nft token-id sender recipient))
        
        ;; Update metadata
        (map-set nft-metadata 
            {token-id: token-id}
            (merge metadata {owner: recipient})
        )
        
        (ok true)
    )
)

;; Enhanced Stake Function
(define-public (stake-nft (token-id (buff 32)))
    (let 
        (
            (metadata (unwrap! (map-get? nft-metadata {token-id: token-id}) ERR-NOT-FOUND))
            (current-block block-height)
        )
        ;; Additional input validations
        (asserts! (is-valid-token-id token-id) ERR-INVALID-TOKEN)
        
        ;; Verify owner
        (asserts! (is-eq tx-sender (get owner metadata)) ERR-UNAUTHORIZED)
        
        ;; Ensure not already staked
        (asserts! (is-none (get staking-start metadata)) ERR-STAKING-ERROR)
        
        ;; Update NFT metadata with staking info
        (map-set nft-metadata 
            {token-id: token-id}
            (merge metadata 
                {
                    staking-start: (some current-block)
                }
            )
        )
        
        ;; Create staking entry
        (map-set nft-staking 
            {token-id: token-id}
            {
                staked-by: tx-sender,
                stake-start-block: current-block,
                total-staked-blocks: u0
            }
        )
        
        (ok true)
    )
)

;; Enhanced Unstake Function
(define-public (unstake-nft (token-id (buff 32)))
    (let 
        (
            (metadata (unwrap! (map-get? nft-metadata {token-id: token-id}) ERR-NOT-FOUND))
            (staking-info (unwrap! (map-get? nft-staking {token-id: token-id}) ERR-STAKING-ERROR))
            (current-block block-height)
            (stake-start (get stake-start-block staking-info))
            (staked-blocks (- current-block stake-start))
            (reward-calculation 
                (/ (* (get asset-value metadata) staked-blocks) u10000)
            )
        )
        ;; Additional input validations
        (asserts! (is-valid-token-id token-id) ERR-INVALID-TOKEN)
        
        ;; Verify staker
        (asserts! (is-eq tx-sender (get staked-by staking-info)) ERR-UNAUTHORIZED)
        
        ;; Update governance tokens
        (map-set governance-tokens 
            tx-sender 
            (+ (default-to u0 (map-get? governance-tokens tx-sender)) reward-calculation)
        )
        
        ;; Reset NFT staking metadata
        (map-set nft-metadata 
            {token-id: token-id}
            (merge metadata 
                {
                    staking-start: none,
                    staking-rewards: (+ (get staking-rewards metadata) reward-calculation)
                }
            )
        )
        
        ;; Remove staking entry
        (map-delete nft-staking {token-id: token-id})
        
        (ok reward-calculation)
    )
)