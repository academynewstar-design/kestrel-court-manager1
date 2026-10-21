// @vitest-environment jsdom
import {afterEach,beforeEach,describe,it,expect,vi} from 'vitest';
import {render,screen,fireEvent,cleanup} from '@testing-library/react';
const rpc=vi.hoisted(()=>vi.fn());
vi.mock('../src/lib/supabase',()=>({supabase:{rpc}}));
import {PaymentFlag,PaymentEvidenceForm} from '../src/PaymentVerification';
afterEach(cleanup);beforeEach(()=>rpc.mockReset());
describe('Payment verification',()=>{
 it('keeps a Paid claim pending until verification exists',()=>{render(<PaymentFlag/>);fireEvent.click(screen.getByRole('button',{name:/Pending verification/}));expect(screen.getByRole('status').textContent).toContain('Paid and Verified are separate');expect(screen.queryByRole('button',{name:'Message Admin'})).toBeNull()});
 it('opens the red explanation on tap and routes to Messages',()=>{const onMessage=vi.fn();render(<PaymentFlag review={{registration_id:4,state:'needs_review'}} onMessage={onMessage}/>);fireEvent.click(screen.getByRole('button',{name:/Needs review/}));expect(screen.getByRole('status').textContent).toContain('does not mean you have not paid');fireEvent.click(screen.getByRole('button',{name:'Message Admin'}));expect(onMessage).toHaveBeenCalledOnce()});
 it('does not disguise a loading failure as verified',()=>{render(<PaymentFlag review={{registration_id:4,state:'verified'}} error="offline"/>);expect(screen.getByRole('button',{name:/Verification unavailable/})).toBeTruthy()});
 it('sends payment evidence for the exact booking and waits for success',async()=>{rpc.mockResolvedValue({error:{message:'Network unavailable'}});const onSent=vi.fn();render(<PaymentEvidenceForm review={{registration_id:4,state:'needs_review'}} onSent={onSent}/>);fireEvent.change(screen.getByLabelText('Payment details'),{target:{value:'Sender: Test Player; CAD 6; ref ABC123; sent Oct 21'}});fireEvent.click(screen.getByRole('button',{name:'Send payment details to Admin'}));expect(await screen.findByRole('alert')).toBeTruthy();expect(onSent).not.toHaveBeenCalled();expect(rpc).toHaveBeenCalledWith('submit_payment_review_message',{p_registration_id:4,p_details:'Sender: Test Player; CAD 6; ref ABC123; sent Oct 21'})});
});
