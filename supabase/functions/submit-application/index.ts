import { createClient } from 'npm:@supabase/supabase-js@2';
const allowedOrigin='https://the-hoon-collective.github.io';
const headers={'Access-Control-Allow-Origin':allowedOrigin,'Access-Control-Allow-Headers':'authorization, x-client-info, apikey, content-type','Access-Control-Allow-Methods':'POST, OPTIONS','Content-Type':'application/json'};
const respond=(status:number,body:unknown)=>new Response(JSON.stringify(body),{status,headers});
Deno.serve(async(req)=>{
 if(req.method==='OPTIONS')return new Response(null,{status:204,headers});
 if(req.method!=='POST')return respond(405,{error:'Method not allowed'});
 if(req.headers.get('origin')!==allowedOrigin)return respond(403,{error:'Origin not allowed'});
 const size=Number(req.headers.get('content-length')||0);
 if(size>12000)return respond(413,{error:'Request too large'});
 let input:Record<string,unknown>;
 try{input=await req.json()}catch{return respond(400,{error:'Invalid JSON'})}
 if(!input||typeof input!=='object'||Array.isArray(input))return respond(400,{error:'Invalid application'});
 const str=(key:string,max=300)=>typeof input[key]==='string'?String(input[key]).trim().slice(0,max):'';
 if(str('website'))return respond(200,{message:'Application received'});
 const full_name=str('fullName',150),preferred_name=str('preferredName',150),email=str('email',254).toLowerCase(),phone=str('phone',40),suburb=str('suburb',120),state=str('state',3),vehicle=str('vehicle',300),interests=str('interests',1500),reason=str('reason',2000),date_of_birth=str('dob',10);
 if(full_name.length<2||!/^\S+@\S+\.\S+$/.test(email)||!phone||!suburb||!['NSW','VIC','QLD','SA','WA','TAS','ACT','NT'].includes(state)||!reason||!/^\d{4}-\d{2}-\d{2}$/.test(date_of_birth))return respond(400,{error:'Please complete all required fields'});
 if(input.prospect!==true||input.conduct!==true||input.accuracy!==true)return respond(400,{error:'Required declarations missing'});
 const dob=new Date(date_of_birth+'T00:00:00Z');if(!Number.isFinite(dob.getTime())||dob.toISOString().slice(0,10)!==date_of_birth)return respond(400,{error:'Invalid date of birth'});
 const now=new Date();let age=now.getUTCFullYear()-dob.getUTCFullYear();if(now.getUTCMonth()<dob.getUTCMonth()||(now.getUTCMonth()===dob.getUTCMonth()&&now.getUTCDate()<dob.getUTCDate()))age--;
 if(age<18||age>120)return respond(400,{error:'Applicants must be at least 18'});
 const turnstileSecret=Deno.env.get('TURNSTILE_SECRET_KEY');
 if(!turnstileSecret)return respond(503,{error:'Application security is not configured'});
 const token=str('turnstileToken',2048);
 if(!token)return respond(400,{error:'Security check required'});
 let challenge;
 try{const verify=await fetch('https://challenges.cloudflare.com/turnstile/v0/siteverify',{method:'POST',headers:{'Content-Type':'application/x-www-form-urlencoded'},body:new URLSearchParams({secret:turnstileSecret,response:token,remoteip:req.headers.get('cf-connecting-ip')||''})});if(!verify.ok)return respond(503,{error:'Security verification unavailable'});challenge=await verify.json()}catch{return respond(503,{error:'Security verification unavailable'})}
 if(!challenge.success||challenge.hostname!=='the-hoon-collective.github.io')return respond(403,{error:'Security check failed. Please retry.'});
 const url=Deno.env.get('SUPABASE_URL'),secret=Deno.env.get('SUPABASE_SERVICE_ROLE_KEY');
 if(!url||!secret)return respond(503,{error:'Application service not configured'});
 const db=createClient(url,secret,{auth:{persistSession:false}});
 const {error}=await db.from('membership_applications').insert({full_name,preferred_name:preferred_name||null,date_of_birth,email,phone,suburb,state,vehicle:vehicle||null,interests:interests||null,reason,prospect_terms_accepted:true,conduct_accepted:true,accuracy_confirmed:true});
 if(error){console.error('Application insert failed',error.code);return respond(503,{error:'Unable to save application. Please try again later.'})}
 return respond(201,{message:'Your application has been received. THC will review it.'});
});
