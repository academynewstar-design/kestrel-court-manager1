import {useEffect,useRef,useState} from 'react';
import {supabase} from './lib/supabase';

const bucket='message-screenshots';
const imageTypes=['image/png','image/jpeg','image/webp'];
export function validateScreenshot(file:File){
 if(!imageTypes.includes(file.type))return 'Choose a PNG, JPG or WebP screenshot.';
 if(file.size>5*1024*1024)return 'The screenshot must be 5 MB or smaller.';
 return '';
}
export async function sendConversationMessage(id:number,sender:string,message:string,file?:File|null){
 let path:string|null=null;
 if(file){
  const invalid=validateScreenshot(file);if(invalid)return {error:{message:invalid}};
  const ext=file.type==='image/jpeg'?'jpg':file.type==='image/webp'?'webp':'png';
  path=`${id}/${sender}/${crypto.randomUUID()}.${ext}`;
  const upload=await supabase.storage.from(bucket).upload(path,file,{contentType:file.type,upsert:false});
  if(upload.error)return {error:upload.error};
 }
 const result=await supabase.from('suggestion_messages').insert({suggestion_id:id,sender_id:sender,message:message.trim()||'Screenshot attached.',attachment_path:path});
 if(result.error&&path)await supabase.storage.from(bucket).remove([path]);
 return result;
}

export function MessageComposer({value,onChange,file,onFile,placeholder,maxLength=2000}:{value:string,onChange:(v:string)=>void,file?:File|null,onFile:(file:File|null)=>void,placeholder:string,maxLength?:number}){
 const [notice,setNotice]=useState('');const input=useRef<HTMLTextAreaElement>(null);
 async function paste(){try{const text=await navigator.clipboard.readText();const el=input.current;const start=el?.selectionStart??value.length;const end=el?.selectionEnd??start;onChange((value.slice(0,start)+text+value.slice(end)).slice(0,maxLength));setNotice('Text pasted.');el?.focus()}catch{setNotice('Press and hold inside the message box, then choose Paste.');input.current?.focus()}}
 return <div className="messagecomposer"><textarea ref={input} aria-label={placeholder} value={value} maxLength={maxLength} onChange={e=>onChange(e.target.value)} placeholder={placeholder}/><div className="rowactions"><button type="button" className="outline" onClick={paste}>Paste text</button><label className="screenshot-picker">📎 Attach screenshot<input type="file" accept="image/png,image/jpeg,image/webp" onChange={e=>{const next=e.target.files?.[0];if(next){const error=validateScreenshot(next);setNotice(error);if(!error)onFile(next)}e.target.value=''}}/></label></div>{file&&<div className="rowactions"><span>{file.name}</span><button type="button" className="outline" onClick={()=>onFile(null)}>Remove screenshot</button></div>}<small className="muted">PNG, JPG or WebP · up to 5 MB. You can also press and hold to select, copy or paste text.</small>{notice&&<p role="status">{notice}</p>}</div>
}

export function MessageAttachment({path}:{path:string}){
 const[url,setUrl]=useState('');const[error,setError]=useState('');
 useEffect(()=>{let active=true;let objectUrl='';supabase.storage.from(bucket).download(path).then(({data,error})=>{if(!active)return;if(error)setError('Screenshot could not be loaded. Refresh to try again.');else if(data){objectUrl=URL.createObjectURL(data);setUrl(objectUrl)}});return()=>{active=false;if(objectUrl)URL.revokeObjectURL(objectUrl)}},[path]);
 return error?<p role="status">{error}</p>:url?<a href={url} target="_blank" rel="noreferrer"><img className="messageattachment" src={url} alt="Attached screenshot"/><span>Open screenshot</span></a>:<p>Loading screenshot…</p>;
}

export function CopyMessage({text}:{text:string}){
 const[status,setStatus]=useState('');
 async function copy(){try{await navigator.clipboard.writeText(text);setStatus('Copied')}catch{const box=document.createElement('textarea');box.value=text;box.style.position='fixed';box.style.opacity='0';document.body.appendChild(box);box.select();try{setStatus(document.execCommand('copy')?'Copied':'Select the message text and choose Copy.')}finally{box.remove()}}}
 return <button type="button" className="outline copy-message" onClick={copy}>{status||'Copy text'}</button>;
}
