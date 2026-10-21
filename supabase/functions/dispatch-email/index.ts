import {createClient} from 'npm:@supabase/supabase-js@2';
// Deploy with Verify JWT OFF; protect with a separate long random dispatch secret.
// Do not configure a scheduler or enable sending until sender domain and recipient tests are complete.
const json=(status:number,body:unknown)=>new Response(JSON.stringify(body),{status,headers:{'content-type':'application/json','cache-control':'no-store'}});
const safe=(s:unknown)=>String(s??'').replace(/[<>]/g,'').slice(0,150);
Deno.serve(async req=>{
 if(req.method!=='POST')return json(405,{error:'Method not allowed'});
 const auth=req.headers.get('authorization');
 const dispatchSecret=Deno.env.get('THC_EMAIL_DISPATCH_SECRET');
 if(!dispatchSecret||!auth||auth!==`Bearer ${dispatchSecret}`)return json(401,{error:'Unauthorized'});
 if(Deno.env.get('THC_EMAIL_SENDING_ENABLED')!=='true')return json(503,{error:'Email sending is disabled'});
 const apiKey=Deno.env.get('RESEND_API_KEY'),sender=Deno.env.get('THC_EMAIL_FROM');
 const url=Deno.env.get('SUPABASE_URL'),key=Deno.env.get('SUPABASE_SERVICE_ROLE_KEY');
 if(!apiKey||!sender||!url||!key)return json(503,{error:'Email service not configured'});
 // Never send from a Resend test address to real applicants.
 if(sender.toLowerCase().includes('resend.dev'))return json(503,{error:'Verified sender domain required'});
 const db=createClient(url,key,{auth:{persistSession:false}});
 const {data,error}=await db.rpc('thc_claim_email');
 if(error){console.error('Queue claim failed',error.code);return json(503,{error:'Queue unavailable'})}
 const item=data?.[0];if(!item)return json(200,{processed:0});
 const name=safe(item.payload?.name)||'there';
 const expiry=item.payload?.expires_at?new Date(item.payload.expires_at).toLocaleDateString('en-AU',{timeZone:'Australia/Sydney'}):'';
 const templates:Record<string,[string,string]>={
 application_received:['THC application received',`Hi ${name},\\n\\nThanks for applying to The Hoon Collective. Your application has been received and will be reviewed.\\n\\nTHC Team`],
 prospect_started:['Your THC prospect period has started',`Hi ${name},\\n\\nYour 30-day prospect period has started. We'll be in touch with the next steps.\\n\\nTHC Team`],
 approved:['Your THC application is approved',`Hi ${name},\\n\\nYour membership application has been approved. Membership becomes active once your $50 annual payment is verified.\\n\\nTHC Team`],
 rejected:['Update on your THC application',`Hi ${name},\\n\\nThank you for your interest. We are unable to approve your application at this time.\\n\\nTHC Team`],
 membership_activated:['THC membership payment recorded',`Hi ${name},\\n\\nYour $50 annual membership payment has been recorded. Your current membership expiry is ${expiry}.\\n\\nTHC Team`],
 renewal_reminder:['THC membership renewal reminder',`Hi ${name},\\n\\nYour THC membership expires on ${expiry}. Contact us about renewing for $50 AUD.\\n\\nTHC Team`]
 };
 const template=templates[item.template];
 if(!template)return json(422,{error:'Unknown template'});
 const [subject,body]=template;
 try{
  const res=await fetch('https://api.resend.com/emails',{method:'POST',headers:{authorization:`Bearer ${apiKey}`,'content-type':'application/json','Idempotency-Key':item.id},body:JSON.stringify({from:sender,to:[item.recipient],reply_to:'thehooncollective@outlook.com',subject,text:body.replaceAll('\\n','\n')})});
  if(!res.ok){await db.from('thc_email_outbox').update({last_error:'Resend HTTP '+res.status,claimed_at:null}).eq('id',item.id);return json(502,{error:'Email provider rejected message',status:res.status})}
  await db.from('thc_email_outbox').update({sent_at:new Date().toISOString(),last_error:null}).eq('id',item.id);
  return json(200,{processed:1});
 }catch{await db.from('thc_email_outbox').update({last_error:'Network error',claimed_at:null}).eq('id',item.id);return json(503,{error:'Email provider unavailable'})}
});
