// @vitest-environment jsdom
import React from 'react';
import {afterEach,describe,it,expect,vi} from 'vitest';
import {render,screen,cleanup} from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import {MessageComposer,CopyMessage,sendConversationMessage} from '../src/MessageTools';
const mock=vi.hoisted(()=>({upload:vi.fn(),remove:vi.fn(),insert:vi.fn()}));
vi.mock('../src/lib/supabase',()=>({supabase:{storage:{from:()=>({upload:mock.upload,remove:mock.remove})},from:()=>({insert:mock.insert})}}));
afterEach(()=>{cleanup();vi.clearAllMocks()});
describe('Private conversation screenshots',()=>{
 it('rejects unsupported files before uploading',async()=>{
  const result=await sendConversationMessage(4,'owner','',new File(['x'],'file.svg',{type:'image/svg+xml'}));
  expect(result.error?.message).toMatch(/PNG, JPG or WebP/);expect(mock.upload).not.toHaveBeenCalled();expect(mock.insert).not.toHaveBeenCalled();
 });
 it('keeps the screenshot attached to the conversation and cleans up a failed message',async()=>{
  mock.upload.mockResolvedValue({error:null});mock.insert.mockResolvedValue({error:{message:'Try again'}});mock.remove.mockResolvedValue({error:null});
  const file=new File(['x'],'screen.png',{type:'image/png'});
  await sendConversationMessage(4,'owner','',file);
  const path=mock.upload.mock.calls[0][0];expect(path).toMatch(/^4\/owner\/.*\.png$/);
  expect(mock.insert).toHaveBeenCalledWith({suggestion_id:4,sender_id:'owner',message:'Screenshot attached.',attachment_path:path});expect(mock.remove).toHaveBeenCalledWith([path]);
 });
 it('selects a screenshot and preserves pasted text at the caret',async()=>{
  const user=userEvent.setup();const change=vi.fn();const onFile=vi.fn();
  render(<MessageComposer value="hello world" onChange={change} onFile={onFile} placeholder="Reply"/>);
  const input=screen.getByRole('textbox') as HTMLTextAreaElement;input.focus();input.setSelectionRange(6,11);
  await navigator.clipboard.writeText('Malli');await user.click(screen.getByRole('button',{name:'Paste text'}));expect(change).toHaveBeenCalledWith('hello Malli');
  const file=new File(['x'],'proof.png',{type:'image/png'});await user.upload(screen.getByLabelText(/Attach screenshot/),file);expect(onFile).toHaveBeenCalledWith(file);
 });
 it('copies a full message',async()=>{
  const user=userEvent.setup();render(<CopyMessage text="Tuesday is missing"/>);await user.click(screen.getByRole('button',{name:'Copy text'}));expect(await navigator.clipboard.readText()).toBe('Tuesday is missing');await screen.findByRole('button',{name:'Copied'});
 });
});
