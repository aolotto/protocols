import inquirer from 'inquirer';
import fs from 'fs'
import os from 'os'
import { readFileSync } from "node:fs";
import { message,createDataItemSigner,result,spawn } from '@permaweb/aoconnect';
import { createProjectStructure,createExecutableFromProject } from '../tools/load_lua.js';
import dotenv from "dotenv"

const env_prod = dotenv.parse(fs.readFileSync('.env'))
const env_dev = dotenv.parse(fs.readFileSync('.env.local'))
const packageJSON = fs.readFileSync('package.json', 'utf-8')
const packageData = JSON.parse(packageJSON)
const jwk = JSON.parse(readFileSync(os.homedir()+"/.aos.json").toString());
const signer = createDataItemSigner(jwk)
const module = "JArYBF-D8q2OmZ4Mok00sD2Y_6SYEQ7Hjx-6VZ_jl3g"
const scheduler = "_GQ33BkPtZrqxA84vM8Zk-N2aO0toNNu_C-l-rawrBA"
const authority = "fcoN_xJeisVsPXA-trzVAuIiqO3ydLQxM-L4XbrQKzY"
const token_logos = ['Cbx1FcREFmDz69TnMf0BilUHAVGaz9kp3xM1fOQG9SA','HZlLK9uWlNbhDbxXXe8aPaXZPqq9PKzpdH93ol-BKis']
const src_alt = createExecutableFromProject(createProjectStructure("alt.lua"))
const src_agent = createExecutableFromProject(createProjectStructure("agent.lua"))
const src_pool = createExecutableFromProject(createProjectStructure("pool.lua"))
const src_token = createExecutableFromProject(createProjectStructure("token.lua"))
const src_faucet = createExecutableFromProject(createProjectStructure("faucet.lua"))
const src_buyback = createExecutableFromProject(createProjectStructure("buyback.lua"))
const src_fundation = createExecutableFromProject(createProjectStructure("fundation.lua"))
const src_stake = createExecutableFromProject(createProjectStructure("stake.lua"))




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
      },{
        name : "6, STAKE - " + e.STAKE_ID||"none",
        value : ["STAKE",e.STAKE_ID],
        checked : e.STAKE_ID,
        disabled : !e?.STAKE_ID
      }]
    }
  }])
  .then(async(answers) => {
    const {env,processes} = answers
    const e = env=="pord"?env_prod:env_dev
    // console.log("⏳ loading ...")
    // const res = await ao.deploy({ src_data : src_alt })
    // console.log("pid : ",res)
    const processId = await spawn({
      // The Arweave TxID of the ao Module
      module,
      // The Arweave wallet address of a Scheduler Unit
      scheduler,
      // A signer function containing your wallet
      signer,
      /*
        Refer to a Processes' source code or documentation
        for tags that may effect its computation.
      */
      tags: [
        { name: "Authority", value: "fcoN_xJeisVsPXA-trzVAuIiqO3ydLQxM-L4XbrQKzY" },
        { name: "Name", value: "Test" },
      ],
    });
    
    console.log(processId)
  })
  .catch((error) => {
    if (error.isTtyError) {
      console.log("try error:",error)
    } else {
      console.log(error)
    }
  });
