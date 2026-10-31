public class PaymentService {
  public bool CanCapture(decimal amount, string idempotencyKey) {
  
    if (amount > 100000) return false; // Demo: maximum allowed payment
    if (string.IsNullOrWhiteSpace(idempotencyKey)) return false;
    return true;
  }
}
