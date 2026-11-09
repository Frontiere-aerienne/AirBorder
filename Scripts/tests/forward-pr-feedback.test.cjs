const {test}=require('node:test'),assert=require('node:assert/strict');
const forward=require('../forward-pr-feedback.cjs');
function fixture({event='issue_comment',body='Please revise this',permission='admin',userType='User',open=true}={}) {
 const c={id:22,body,user:{type:userType,login:'owner'},html_url:'https://github.com/owner/repo/pull/1#discussion_r22'};
 const context={eventName:event,repo:{owner:'owner',repo:'repo'},payload:event==='issue_comment'?{comment:c,issue:{number:1,pull_request:{}}}:event==='pull_request_review'?{review:c,pull_request:{number:1}}:{comment:c,pull_request:{number:1}}};
 const posted=[],existing=[];
 const github={rest:{repos:{getCollaboratorPermissionLevel:async()=>({data:{permission}})},pulls:{get:async()=>({data:{state:open?'open':'closed'}})},issues:{listComments(){},createComment:async x=>{posted.push(x);existing.push(x);return{data:{html_url:'https://github.com/owner/repo/pull/1#new'}};}}},paginate:async()=>existing};
 return {github,context,core:{notice(){}},posted};
}
for(const event of ['issue_comment','pull_request_review_comment','pull_request_review'])test(`authorized ${event} alerts once and changed feedback alerts again`,async()=>{
 const f=fixture({event});await forward(f);await forward(f);assert.equal(f.posted.length,1);const c=f.context.payload.comment||f.context.payload.review;c.body='Updated feedback';await forward(f);assert.equal(f.posted.length,2);assert.match(f.posted[0].body,/@codex/);assert.match(f.posted[0].body,/do not modify files, push changes, approve, or merge/);
});
for(const options of [{permission:'read'},{permission:'triage'},{userType:'Bot'},{body:'@codex review'},{body:'<!-- airborder-codex-feedback:existing -->'},{body:'Fixed X.\n\n_🤖 Addressed by [Claude Code](https://claude.com/claude-code)_'},{body:'Summary\n\n🤖 Generated with [Claude Code](https://claude.com/claude-code)'},{body:'<!-- report-rubric-check -->\nresults'},{body:' '},{open:false}])test(`ignore ${JSON.stringify(options)}`,async()=>{const f=fixture(options);await forward(f);assert.equal(f.posted.length,0);});
test('ordinary issues and unrelated URLs cannot trigger forwarding',async()=>{
 const f=fixture();delete f.context.payload.issue.pull_request;await forward(f);assert.equal(f.posted.length,0);
 const g=fixture();g.context.payload.comment.html_url='https://other.example/pull/1';await assert.rejects(()=>forward(g),/Unexpected feedback URL/);assert.equal(g.posted.length,0);
});
