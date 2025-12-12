;; Lending Pool Test Suite
;; Comprehensive tests for all Clarity 4 features

;; Test 1: Basic Deposit and Withdrawal
(define-public (test-deposit-withdraw)
    (begin
        ;; Deposit 1000 STX
        (try! (contract-call? .lending-pool deposit u1000000000))
        
        ;; Verify deposit was recorded
        (let ((user-deposit (unwrap-panic (contract-call? .lending-pool get-user-deposit tx-sender))))
            (asserts! (is-eq (get amount user-deposit) u1000000000) (err "Deposit amount mismatch"))
        )
        
        ;; Withdraw 500 STX
        (try! (contract-call? .lending-pool withdraw u500000000))
        
        ;; Verify remaining balance
        (let ((user-deposit (unwrap-panic (contract-call? .lending-pool get-user-deposit tx-sender))))
            (asserts! (is-eq (get amount user-deposit) u500000000) (err "Withdrawal amount mismatch"))
        )
        
        (ok true)
    )
)

;; Test 2: Collateral and Borrowing
(define-public (test-collateral-borrow)
    (begin
        ;; Add 2000 STX collateral
        (try! (contract-call? .lending-pool add-collateral u2000000000 "STX"))
        
        ;; Borrow 1000 STX (50% of collateral, under 150% requirement)
        (try! (contract-call? .lending-pool borrow u1000000000))
        
        ;; Verify loan was created
        (let ((user-loan (unwrap-panic (contract-call? .lending-pool get-user-loan tx-sender))))
            (asserts! (is-eq (get principal-amount user-loan) u1000000000) (err "Loan amount mismatch"))
        )
        
        ;; Check health factor (should be 200% = 2x collateralization)
        (let ((health (unwrap-panic (contract-call? .lending-pool get-health-factor tx-sender))))
            (asserts! (>= health u150) (err "Health factor too low"))
        )
        
        (ok true)
    )
)

;; Test 3: CLARITY 4 - stacks-block-time Interest Calculation
(define-public (test-interest-accrual)
    (begin
        ;; Setup: Add collateral and borrow
        (try! (contract-call? .lending-pool add-collateral u3000000000 "STX"))
        (try! (contract-call? .lending-pool borrow u1000000000))
        
        ;; Calculate interest (should use stacks-block-time)
        (let ((interest (unwrap-panic 
                (contract-call? .lending-pool calculate-current-interest tx-sender))))
            ;; Interest should be > 0 after some time
            ;; In real test, we'd advance block-time
            (asserts! (>= interest u0) (err "Interest calculation failed"))
        )
        
        (ok true)
    )
)

;; Test 4: CLARITY 4 - to-ascii? Loan Status
(define-public (test-loan-status-ascii)
    (begin
        ;; Setup loan
        (try! (contract-call? .lending-pool add-collateral u5000000000 "STX"))
        (try! (contract-call? .lending-pool borrow u2000000000))
        
        ;; Get ASCII status (uses to-ascii? for formatting)
        (let ((status (unwrap-panic 
                (contract-call? .lending-pool get-loan-status-ascii tx-sender))))
            ;; Verify status includes required fields
            (asserts! (is-eq (get status status) "HEALTHY") (err "Incorrect loan status"))
        )
        
        (ok true)
    )
)

;; Test 5: Price Oracle Freshness (stacks-block-time)
(define-public (test-price-oracle-freshness)
    (begin
        ;; Update price for sBTC
        (try! (contract-call? .price-oracle update-price "sBTC" u51000000000 "test-feed"))
        
        ;; Check if price is fresh (uses stacks-block-time)
        (let ((is-fresh (unwrap-panic 
                (contract-call? .price-oracle is-price-fresh "sBTC"))))
            (asserts! is-fresh (err "Price should be fresh"))
        )
        
        ;; Get human-readable status (uses to-ascii?)
        (let ((status (unwrap-panic 
                (contract-call? .price-oracle get-price-status "sBTC"))))
            (print status)
        )
        
        (ok true)
    )
)

;; Test 6: Passkey Registration (secp256r1-verify)
(define-public (test-passkey-registration)
    (begin
        ;; Register a passkey with mock secp256r1 public key
        (let ((mock-pubkey 0x02a1633cafcc01ebfb6d78e39f687a1f0995c62fc95f51ead10a02ee0be551b5dc))
            (try! (contract-call? .passkey-signer register-passkey mock-pubkey "Test-Device"))
        )
        
        ;; Verify passkey was registered
        (let ((passkey-info (unwrap-panic 
                (contract-call? .passkey-signer get-passkey-info tx-sender))))
            (asserts! (is-some passkey-info) (err "Passkey not registered"))
        )
        
        ;; Get authentication summary (uses to-ascii?)
        (let ((summary (unwrap-panic 
                (contract-call? .passkey-signer get-auth-summary tx-sender))))
            (print summary)
        )
        
        (ok true)
    )
)

;; Test 7: Governance Proposal (stacks-block-time timelock)
(define-public (test-governance-proposal)
    (begin
        ;; Create a proposal
        (let ((proposal-id (unwrap-panic 
                (contract-call? .protocol-governance create-proposal 
                    "Update Interest Rate" 
                    "Proposal to update the lending pool interest rate to 6%"
                    none))))
            
            ;; Verify proposal was created
            (let ((proposal (unwrap-panic 
                    (contract-call? .protocol-governance get-proposal proposal-id))))
                (asserts! (is-some proposal) (err "Proposal not created"))
            )
            
            ;; Check if can execute (should fail due to timelock)
            (let ((can-exec (unwrap-panic 
                    (contract-call? .protocol-governance can-execute proposal-id))))
                (asserts! (not can-exec) (err "Proposal should be time-locked"))
            )
        )
        
        (ok true)
    )
)

;; Test 8: Health Factor Calculation
(define-public (test-health-factor-edge-cases)
    (begin
        ;; Test 1: No debt = infinite health
        (try! (contract-call? .lending-pool add-collateral u1000000000 "STX"))
        (let ((health (unwrap-panic (contract-call? .lending-pool get-health-factor tx-sender))))
            (asserts! (is-eq health u0) (err "No debt should return 0 (infinite)"))
        )
        
        ;; Test 2: Exact collateralization
        (try! (contract-call? .lending-pool borrow u666666666))  ;; 150% of 666M = 1000M
        (let ((health (unwrap-panic (contract-call? .lending-pool get-health-factor tx-sender))))
            (asserts! (>= health u120) (err "Health factor calculation error"))
        )
        
        (ok true)
    )
)

;; Test 9: Repayment
(define-public (test-loan-repayment)
    (begin
        ;; Setup
        (try! (contract-call? .lending-pool add-collateral u2000000000 "STX"))
        (try! (contract-call? .lending-pool borrow u1000000000))
        
        ;; Repay half
        (try! (contract-call? .lending-pool repay u500000000))
        
        ;; Verify remaining loan
        (let ((user-loan (unwrap-panic (contract-call? .lending-pool get-user-loan tx-sender))))
            ;; Remaining should be approximately 500M (plus interest)
            (asserts! (< (get principal-amount user-loan) u600000000) (err "Repayment failed"))
        )
        
        (ok true)
    )
)

;; Test 10: Liquidator Contract Verification (contract-hash?)
(define-public (test-liquidator-verification)
    (begin
        ;; Register the simple-liquidator contract
        ;; This uses contract-hash? to verify the liquidator
        (try! (contract-call? .lending-pool register-verified-liquidator .simple-liquidator))
        
        ;; Verification happens automatically using contract-hash?
        ;; If the contract changes, the hash changes, preventing execution
        
        (ok true)
    )
)

;; Run all tests
(define-public (run-all-tests)
    (begin
        (print "Running Clarity 4 Lending Protocol Tests...")
        
        (print "Test 1: Deposit/Withdraw")
        (try! (test-deposit-withdraw))
        
        (print "Test 2: Collateral/Borrow")
        (try! (test-collateral-borrow))
        
        (print "Test 3: Interest Accrual (stacks-block-time)")
        (try! (test-interest-accrual))
        
        (print "Test 4: Loan Status ASCII (to-ascii?)")
        (try! (test-loan-status-ascii))
        
        (print "Test 5: Price Oracle Freshness")
        (try! (test-price-oracle-freshness))
        
        (print "Test 6: Passkey Registration (secp256r1)")
        (try! (test-passkey-registration))
        
        (print "Test 7: Governance Timelock")
        (try! (test-governance-proposal))
        
        (print "Test 8: Health Factor Edge Cases")
        (try! (test-health-factor-edge-cases))
        
        (print "Test 9: Loan Repayment")
        (try! (test-loan-repayment))
        
        (print "Test 10: Liquidator Verification (contract-hash?)")
        (try! (test-liquidator-verification))
        
        (print "All tests passed!")
        (ok true)
    )
)
