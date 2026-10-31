CREATE PROCEDURE CapturePayment @IdempotencyKey NVARCHAR(100), @Amount DECIMAL(18,2)
AS
BEGIN
 IF @Amount <= 0 THROW 50001, 'Amount must be positive', 1;
 IF EXISTS (SELECT 1 FROM Payments WHERE IdempotencyKey = @IdempotencyKey)
  THROW 50002, 'Duplicate payment', 1;
 INSERT INTO Payments (IdempotencyKey, Amount) VALUES (@IdempotencyKey, @Amount);
END;
