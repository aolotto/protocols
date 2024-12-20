import inquirer from 'inquirer';
import fs from 'fs'
import { readFileSync } from "node:fs";
import { AO } from "wao"
import { createProjectStructure,createExecutableFromProject } from '../tools/load_lua.js';
import dotenv from "dotenv"

const env_prod = dotenv.parse(fs.readFileSync('.env'))
const env_dev = dotenv.parse(fs.readFileSync('.env.local'))
const packageJSON = fs.readFileSync('package.json', 'utf-8')
const packageData = JSON.parse(packageJSON)
const jwk = JSON.parse(readFileSync("../.aos.json").toString());
const ao = await new AO().init(jwk)
const signer = ao.toSigner(jwk)
const module = "Do_Uc2Sju_ffp6Ev0AnLVdPtot15rvMjP-a9VVaA5fM"
const scheduler = "_GQ33BkPtZrqxA84vM8Zk-N2aO0toNNu_C-l-rawrBA"
const authority = "fcoN_xJeisVsPXA-trzVAuIiqO3ydLQxM-L4XbrQKzY"
const token_logos = ['Cbx1FcREFmDz69TnMf0BilUHAVGaz9kp3xM1fOQG9SA','HZlLK9uWlNbhDbxXXe8aPaXZPqq9PKzpdH93ol-BKis']
const src_agent = createExecutableFromProject(createProjectStructure("agent.lua"))
const src_pool = createExecutableFromProject(createProjectStructure("pool.lua"))
const src_token = createExecutableFromProject(createProjectStructure("token.lua"))
const src_faucet = createExecutableFromProject(createProjectStructure("faucet.lua"))
const src_buyback = createExecutableFromProject(createProjectStructure("buyback.lua"))
const src_fundation = createExecutableFromProject(createProjectStructure("fundation.lua"))



inquirer
  .prompt([{
    type:"select",
    name: "env",
    message: "choose an environment of the project to load:",
    choices: [ "dev", "prod" ]
  },{
    type: "checkbox",
    name: "processes",
    message: "choose the processes to load :",
    choices: (answers) => {
      const {env} = answers
      const e = env == "prod"? env_prod : env_dev
      return [{
        name : "1, AGENT - " + e.AGENT_ID||"none",
        value : ["AGENT",e.AGENT_ID],
        checked : e.AGENT_ID,
        disabled : !e?.AGENT_ID
      },{
        name : "2, POOL - " + e.POOL_ID||"none",
        value : ["POOL",e.POOL_ID],
        checked : e.POOL_ID,
        disabled : !e?.POOL_ID
      },{
        name : "3, FAUCET - " + e.FAUCET_ID||"none",
        value : ["FAUCET",e.FAUCET_ID],
        checked : e.FAUCET_ID,
        disabled : !e?.FAUCET_ID
      },{
        name : "4, FUNDATION - " + e.FUNDATION_ID||"none",
        value : ["FUNDATION",e.FUNDATION_ID],
        checked : e.FUNDATION_ID,
        disabled : !e?.FUNDATION_ID
      },{
        name : "5, BUYBACK - " + e.BUYBACK_ID||"none",
        value : ["BUYBACK",e.BUYBACK_ID],
        checked : e.BUYBACK_ID,
        disabled : !e?.BUYBACK_ID
      }]
    }
  }])
  .then(async(answers) => {
    const {env,processes} = answers
    const e = env=="pord"?env_prod:env_dev
    console.log("loading ...")
    processes.forEach(async element => {
      const [key,pid] = element
      let data,fills
      switch(key){
        case "AGENT":
          const paytoken_pid = e.PAY_ID || (env=="pord"?"7zH9dlMNoxprab9loshv3Y7WG45DOny_Vrq9KrXObdQ":"KCAqEdXfGoWZNhtgPRIL0yGgWlCDUl0gvHu8dnE5EJs")
          data = src_agent[0],
          fills = {DEFAULT_PAY_TOKEN_ID: paytoken_pid} 
        break;
        case "POOL":
          data = src_pool[0]
          fills = {AGENT:e.AGENT_ID}
        break;
        case "FAUCET":
          data = src_faucet[0]
          fills = {AGENT:e.AGENT_ID}
        break;
        case "FUNDATION":
          data = src_fundation[0]
          fills = {AGENT:e.AGENT_ID}
        break;
        case "BUYBACK":
          data = src_buyback[0]
          fills = {AGENT:e.AGENT_ID}
        break;
      }

      const { err,mid } = await ao.load({ data,fills, pid })
      if(err){throw(err)}
      console.log("✓ loaded: " + mid + " > " + pid + " ("+key+")")
      
    });
    

  })
  .catch((error) => {
    if (error.isTtyError) {
      console.log("try error:",error)
    } else {
      console.log(error)
    }
  });
