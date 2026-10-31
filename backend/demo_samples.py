"""Stable UI demonstration inputs, independent of editable GitHub guard samples.

The files under samples/ intentionally change during the PR approval demo.
They are evaluated by app/approval.py and must not define UI test fixtures.
"""

PAYMENT_BEFORE = 'public class PaymentService {\n  public bool CanCapture(decimal amount, string idempotencyKey) {\n    if (amount <= 0) return false;\n    if (amount > 100000) return false; // Demo: maximum allowed payment\n    if (string.IsNullOrWhiteSpace(idempotencyKey)) return false;\n    return true;\n  }\n}\n'

SQL_BEFORE = "CREATE PROCEDURE CapturePayment @IdempotencyKey NVARCHAR(100), @Amount DECIMAL(18,2)\nAS\nBEGIN\n IF @Amount <= 0 THROW 50001, 'Amount must be positive', 1;\n IF EXISTS (SELECT 1 FROM Payments WHERE IdempotencyKey = @IdempotencyKey)\n  THROW 50002, 'Duplicate payment', 1;\n INSERT INTO Payments (IdempotencyKey, Amount) VALUES (@IdempotencyKey, @Amount);\nEND;\n"
