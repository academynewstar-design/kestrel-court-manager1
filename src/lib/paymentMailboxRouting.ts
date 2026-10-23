/** Payment notification mailbox routing. Keep this decision server-side for verification. */
export const PAYMENT_INBOXES = {
  primary: 'academynewstar@gmail.com',
  londonVolleyball: 'kheynand@gmail.com',
} as const;

export type PaymentSession = {
  sport?: string | null;
  city?: string | null;
};

/** Only London volleyball uses the secondary mailbox; London badminton stays primary. */
export function paymentInboxForSession(session: PaymentSession): string {
  const sport = (session.sport ?? '').trim().toLowerCase();
  const city = (session.city ?? '').trim().toLowerCase();
  return sport === 'volleyball' && (city === 'london' || city === 'london, ontario')
    ? PAYMENT_INBOXES.londonVolleyball
    : PAYMENT_INBOXES.primary;
}
