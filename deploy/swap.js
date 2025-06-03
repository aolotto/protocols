import inquirer from 'inquirer';
import { connect } from '@permaweb/aoconnect'
import BN from 'bignumber.js'
const defaultAOConfig = {
  CU_URL: 'https://cu.ao-testnet.xyz',
  MU_URL: 'https://mu.ao-testnet.xyz',
  GATEWAY_URL: 'https://g8way.io:443'
}
const ao = connect(defaultAOConfig)
const LP_PROCESS = '2sWVPeUTYuB0VMrkgC9m_0MwljaZqEJdAfgJXNZgEIw'

console.log(`🔄 Fetching LP info...`)

const lp = await ao.dryrun({
  process: LP_PROCESS,
  tags: [
    { name: 'Action', value: 'Info' },
  ]
})

const lp_data = {}
for (const {name,value} of lp?.Messages?.[0]?.Tags) {
  lp_data[name] = value
}
console.log(`X: ${lp_data.SymbolX}, Y: ${lp_data.SymbolY}, DecimalX: ${lp_data.DecimalX}, DecimalY: ${lp_data.DecimalY}`)
// const lp_data = JSON.parse(res.Messages[0]['lp_data'])

const px = lp_data.PX
const py = lp_data.PY
const DecimalX = lp_data.DecimalX
const DecimalY = lp_data.DecimalY
const pxUnitBN = new BN(px).dividedBy(new BN(10).pow(DecimalX))
const pyUnitBN = new BN(py).dividedBy(new BN(10).pow(DecimalY))
const xy_price = pxUnitBN.dividedBy(pyUnitBN).toString()
console.log(`Current price: ${xy_price} ${lp_data.SymbolX} per ${lp_data.SymbolY}`)
const yx_price = pyUnitBN.dividedBy(pxUnitBN).toString()
console.log(`Current price: ${yx_price} ${lp_data.SymbolY} per ${lp_data.SymbolX}`)


inquirer
  .prompt([
    { type: "select", name: "direction", message: "Choose the direction of the swap:", choices: [`${lp_data.SymbolX} to ${lp_data.SymbolY}`, `${lp_data.SymbolY} to ${lp_data.SymbolX}`] },
    { type: "input", name: "amount", message: `Enter the amount you want to swap:` }
  ])
  .then(async (answers) => {
    const amount = answers.amount
    console.log(`Swapping ${amount} ${answers.direction}...`)
    // const amountBN = new BN(amount).multipliedBy(new BN(10).pow(DecimalX))
    // const res = await ao.dryrun({
    //   process: pool,
    //   tags: [
    //     { name: 'Action', value: 'Swap' },
    //     { name: 'Amount', value: amountBN.toString() }
    //   ]
    // })
    // console.log(res)
  })