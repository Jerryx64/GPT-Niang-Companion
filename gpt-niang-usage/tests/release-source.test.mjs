import test from 'node:test';
import assert from 'node:assert/strict';
import {latestRelease, RELEASE_API, RELEASE_FEED, allowedUrl, selectRelease} from '../runtime/update.mjs';
test('the fork checks its own public release feed when REST quota is unavailable', async()=>{
  const calls=[];
  const release={tag_name:'v1.4.0',draft:false,prerelease:false,assets:[
    {name:'gpt-niang-usage-widget-v1.4.0-windows.zip',size:123,browser_download_url:'https://github.com/Jerryx64/GPT-Niang-Companion/releases/download/v1.4.0/gpt-niang-usage-widget-v1.4.0-windows.zip'},
    {name:'SHA256SUMS.txt',size:100,browser_download_url:'https://github.com/Jerryx64/GPT-Niang-Companion/releases/download/v1.4.0/SHA256SUMS.txt'}
  ]};
  const result=await latestRelease(async(url)=>{
    calls.push(url);
    if(url===RELEASE_API)throw Object.assign(new Error('Forbidden'),{statusCode:403});
    assert.equal(url,RELEASE_FEED);return Buffer.from(JSON.stringify(release));
  });
  assert.deepEqual(calls,[RELEASE_API,RELEASE_FEED]);
  assert.equal(selectRelease(result,'1.3.4').version,'1.4.0');
  assert.throws(()=>allowedUrl('https://github.com/T7moris/GPT-Niang/releases/download/v1.4.0/other.zip'));
  await assert.rejects(latestRelease(async()=>{throw Object.assign(new Error('Not found'),{statusCode:404});}),/Not found/);
});
