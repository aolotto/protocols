local utils = require("modules.utils")

-- data structures of initialization
local initial_user = {
  div = { 0, 0, 0 }, -- unpay, total dividends,paid
  bet = { 0, 0, 0 }, -- bets: {counts,amount,tickets}
  mint = 0, -- total mint
  win = { 0, 0, 0 }, -- wins: {balance, increased, decreased}
  tax = { 0, 0, 0 }, -- taxs: {balance, Increased, decreased}
  faucet = { 0, 0}, -- facucet quota : {balance, increased}
}
local initial_stats = {
  total_players = 0,
  total_sales_amount = 0,
  total_tickets = 0,
  total_archived_round = 0,
  total_reward_amount = 0,
  total_reward_count = 0,
  total_matched_draws = 0,
  total_unmatched_draws = 0,
  ts_pool_start = 0,
  ts_latest_bet = 0,
  ts_lastst_draw = 0,
  total_claimed_amount = 0,
  total_claimed_count = 0,
  total_winners = 0,
  total_minted_amount = 0,
  total_minted_count = 0,
  total_faucet_account = 0,
  dividends = {0,0,0},
  buybacks = {0,0,0},
  total_burned = 0,
  total_distributed = 0,
  total_taxation = 0,
  launch_time = 1735689601000
}

-- consts
DEFAULT_PAY_TOKEN_ID = DEFAULT_PAY_TOKEN_ID or "<DEFAULT_PAY_TOKEN_ID>"
FUNDATION_ID = FUNDATION_ID or "<FUNDATION_ID>"
FAUCET_ID = FAUCET_ID or "<FAUCET_ID>"
BUYBACK_ID = BUYBACK_ID or "<BUYBACK_ID>"
POOL_ID = POOL_ID or "<POOL_ID>"
MINT_TAX = MINT_TAX or "0.2"
MAX_MINT = "210000000000000000000"
BET2MINT_QUOTA_RATE = BET2MINT_QUOTA_RATE or "0.002"
PER_MINT_BASE_RATE = PER_MINT_BASE_RATE or "0.001"


-- global tables
Quota = Quota or {0,0} -- {balance, initial}
Players = Players or {}
Stats = Stats or utils.deepCopy(initial_stats)
Funds = Funds or {}
Winners = Winners or {}
-- Pools = Pools or {}
Sponsors = Sponsors or {}
TopBettings = TopBettings or {}
TopMintings = TopMintings or {}
TopDividends = TopDividends or {}
TopWinnings = TopWinnings or {}
TokenInfo = TokenInfo or {}
SyncedInfo = SyncedInfo or {}


-- bet_to_mint
local function countBets(uid,quantity,pool)
  assert(type(uid)=="string","Missed user id")
  if not Players[uid] then 
    Players[uid] = utils.deepCopy(initial_user)
    utils.increase(Stats,{total_players=1})
  end
  local _tax_rate = pool and tonumber(pool['Tax-Rate']) or 0.4
  local _limit = pool and tonumber(pool['Max-Bet']) or 100
  local _price = pool and tonumber(pool.Price) or 1000000
  local count = math.min(math.floor(utils.toNumber(quantity) / _price),_limit)
  local amount = _price * count
  local tax = amount * _tax_rate
  utils.increase(Players[uid].bet,{count,amount,1})
  utils.increase(Stats,{
    total_sales_amount = amount,
    total_tickets = 1,
  })
  if not Stats.dividends then Stats.dividends = {0,0,0} end
  if not Stats.buybacks then Stats.buybacks = {0,0,0} end
  utils.increase(Stats.dividends,{tax*0.5,tax*0.5,0})
  utils.increase(Stats.buybacks,{tax*0.5,tax*0.5,0})
  utils.update(Stats,{ts_latest_bet = os.time()})
  utils.updateRanking(TopBettings,uid,Players[uid].bet[2],50) -- update rankings
  return tostring(count), tostring(amount), tostring(tax)
end

local function resetQuota()
  local quota = (utils.toNumber(MAX_MINT) * 0.9 - utils.toNumber(TotalSupply)) * utils.toNumber(BET2MINT_QUOTA_RATE)
  Quota = {quota,quota}
  return Quota
end

local function Mint(count,uid)
  assert(type(uid)=="string","Missed user id")
  assert(tonumber(count)>=1,"Missed count")
  if not Players[uid] then 
    Players[uid] = utils.deepCopy(initial_user)
    utils.increase(Stats,{total_players=1})
  end
  local _count = utils.toNumber(count)
  local _speed = (utils.toNumber(MAX_MINT) - utils.toNumber(TotalSupply)) / utils.toNumber(MAX_MINT)
  local _player = Players[uid]
  
 
  local _quota_balance =  Quota[1] or 0
  local _unit = math.max(_quota_balance * utils.toNumber(PER_MINT_BASE_RATE) * _speed,1)
  local _MINT_TAX = utils.toNumber(MINT_TAX) or 0.2
  
  local _minted = math.min(_unit * _count,_quota_balance)
  local _faucet_buff = 0
  if _player.faucet[1]>0 then
    _faucet_buff = math.min(_player.faucet[1] ,_minted)
    utils.decrease(Players[uid].faucet,{_faucet_buff,0})
  end
  _minted = _minted + _faucet_buff
  local user_minted = string.format("%.0f", _minted * (1-_MINT_TAX))
  local fundation_minted = string.format("%.0f", _minted * _MINT_TAX)
  local total_minted = utils.add(user_minted,fundation_minted)
  -- decrease minting quota
  utils.decrease(Quota,{utils.toNumber(total_minted),0})
  -- increase total minted
  utils.increase(Stats,{
    total_minted_amount = utils.toNumber(total_minted),
    total_minted_count = 1
  })
  -- increase player minted
  utils.increase(Players[uid],{mint=utils.toNumber(user_minted)})
  -- Increase total supply
  TotalSupply = utils.add(TotalSupply,total_minted)
  -- Increase user balance
  if not Balances[uid] then 
    Balances[uid] = "0"
  end
  Balances[uid] = utils.add(Balances[uid], user_minted)
  -- Increase fundation balance
  local _fundation = FUNDATION_ID or ao.id
  if not Balances[_fundation] then 
    Balances[_fundation] = "0"
  end
  Balances[_fundation] = utils.add(Balances[_fundation], fundation_minted)
  -- updating rankings
  utils.updateRanking(TopMintings,uid,Players[uid].mint,50) -- update rankings
  -- return minted result
  return total_minted, user_minted, fundation_minted, tostring(_speed), tostring(_unit), tostring(_MINT_TAX), _faucet_buff>0 and tostring(_faucet_buff) or nil
end



Handlers.add("bet2mint",{
  Action="Credit-Notice",
  From = function (_from)
    return DEFAULT_PAY_TOKEN_ID == _from
  end,
  Sender = function (_sender) return _sender ~= Owner and _sender ~= ao.id end,
  Quantity = function(_quantity,m)
    local id = POOL_ID or m['X-Pool']
    local price = SyncedInfo[id].Price
    return tonumber(_quantity) >= tonumber(price)
  end,
  ['X-Numbers'] = "_"
},function (msg)
  -- assert(msg.Timestamp >= Stats.launch_time or 0,"The game is not started yet")
  local _pay_token_id = msg.From
  if not Funds[_pay_token_id] then Funds[_pay_token_id] = 0 end
  utils.increase(Funds,{[_pay_token_id]=utils.toNumber(msg.Quantity)})
  local _pool_id = msg['X-Pool'] or POOL_ID
  local _pool = SyncedInfo[_pool_id]
  local _player = msg['X-Beneficiary'] or msg.Sender
  local _minter = msg.Sender

  local _count,_amount,_tax = countBets(_player, msg.Quantity, _pool)
  local _message = {
    Action = "Save-Ticket",
    Count = tostring(_count),
    Amount = tostring(_amount),
    Tax = tostring(_tax),
    Price = _pool.Price,
    Player = _player
  }

  if Quota[2]==0 and utils.toNumber(TotalSupply)==0 then 
    resetQuota() 
    print("Quota reseted")
  end -- minting begining by the first bet

  local mint = nil
  if Quota[1]>0 or Players[_minter].faucet[1]>0 then
   
    local _minted, _user_minted, _fundation_minted, _speed, _unit, _mint_tax_rate, _mint_buff = Mint(_count, _minter)
    
    if utils.toNumber(_minted) > 0 and _player == _minter then
      mint = {
        total = _minted,
        unit = _unit,
        mint_tax_rate = _mint_tax_rate,
        speed = _speed,
        amount = _user_minted,
        buff = _mint_buff,
        ticker = Ticker,
        token = ao.id,
        denomination = Denomination
      }
    end

    _message.Mint = ao.id
    _message['Mint-Total'] = _minted
    _message['Mint-Buff'] = _mint_buff
    _message['Mint-Speed'] = _speed
    _message['Mint-Amount'] = _user_minted
    _message['Mint-Fundation'] = _fundation_minted
    _message['Mint-For'] = _minter
  end
  _message.Data = {
    token = {
      id = SyncedInfo[_pay_token_id].Id,
      ticker = SyncedInfo[_pay_token_id].Ticker,
      denomination = SyncedInfo[_pay_token_id].Denomination
    },
    minted = mint,
    minting = {
      quota = Quota,
      max_mint = MAX_MINT,
      minted = TotalSupply
    },
    sponsor = _player ~= msg.Sender and Sponsors[msg.Sender] or nil
  }
  msg.forward(_pool_id,_message)
end)



-- facucet
Handlers.add("add_faucet_quota",{
  From = function (_from) return _from == FAUCET_ID and _from ~= ao.id end,
  Action = "Add-Faucet-Quota",
  Quantity = "%d+",
  Account = function (_account) return _account ~= Owner and #_account == 43 and _account ~= ao.id end
},function (msg)
  local uid = msg.Account
  local qty = math.min(utils.toNumber(msg.Quantity),2100000000000000)
  if not Players[uid] then 
    Players[uid] = utils.deepCopy(initial_user) 
    utils.increase(Stats,{total_players=1})
  end
  utils.increase(Players[uid].faucet,{qty,qty})
  utils.increase(Stats,{total_faucet_account=1})
  msg.reply({
    Action="Faucet-Quota-Added",
    User = msg.User,
    Account = msg.Account,
    Quantity = tostring(qty)
  })
end)


-- querys
Handlers.add("get-player",{
  Action = "Get-Player",
  Player = "_"
},function (msg)
  msg.reply({Data = Players[msg.Player]})
end)

Handlers.add("ranks","Ranks",function(msg)
  local ranks = {
    bettings = TopBettings,
    winnings = TopWinnings,
    mintings = TopMintings,
    dividends = TopDividends
  }
  msg.reply({ Data=ranks})
end)

Handlers.add("stats","Stats",function(msg)
  local stats = Stats
  stats.total_supply = TotalSupply
  msg.reply({Data=stats})
end)

Handlers.add("protocols","Protocols",function (msg)
  local details = SyncedInfo
  details[ao.id] = {
    Id = ao.id,
    Ticker = Ticker,
    Denomination = Denomination,
    Logo = Logo
  }
  msg.reply({
    Data = {
      agent_id = ao.id,
      pay_id = DEFAULT_PAY_TOKEN_ID,
      pool_id = POOL_ID,
      facuet_id = FAUCET_ID,
      fundation_id = FUNDATION_ID,
      buybacks_id = BUYBACK_ID,
      owner_id = Owner,
      details = details
    }
  })
end)



-- the tools of management

Handlers.syncInfo = function(pids)
  for i, v in ipairs(pids) do
    Send({
      Target = v,
      Action = "Info"
    }).onReply(function(msg)
      SyncedInfo[msg.From] = msg.Tags
      SyncedInfo[msg.From].Id = msg.From
    end)
  end
end

Handlers.addSponsor = function(id,name,desc,url)
  if not Sponsors[id] then
    Sponsors[id] = {}
  end
  utils.update(Sponsors[id],{
    id = id,
    name = name or Sponsors[id].name,
    desc = desc or Sponsors[id].desc,
    url = url or Sponsors[id].url
  })
  print("Sponsor added!")
end


-- claim
local function doClaim(claim)
  Handlers.once('once_claimed_'..claim.id,{
    Action = "Debit-Notice",
    From = DEFAULT_PAY_TOKEN_ID,
    Recipient = claim.recipient,
    ['X-Player'] = claim.player,
    ['X-Transfer-Type'] = "Claim-Notice",
    ['X-Claim-Id'] = claim.id,
    Quantity = tostring(claim.quantity)
  },function(m)
    local _qty = tonumber(m.Quantity)
    local _tax = tonumber(m['X-Tax'])
    Claims[m['X-Claim-Id']] = nil
    if not Funds[DEFAULT_PAY_TOKEN_ID] then Funds[DEFAULT_PAY_TOKEN_ID] = 0 end
    utils.decrease(Funds,{[DEFAULT_PAY_TOKEN_ID]=_qty})
    if not Stats.total_taxation then
      Stats.total_taxation = 0
    end
    utils.increase(Stats,{
      total_claimed_count = 1,
      total_claimed_amount = tonumber(m['X-Amount']),
      total_taxation = _tax
    })
  end)
  Send({
    Target = DEFAULT_PAY_TOKEN_ID,
    Action = "Transfer",
    Quantity=string.format("%.0f",claim.quantity),
    Recipient = claim.recipient,
    ['X-Amount']=tostring(claim.amount),
    ['X-Tax']=tostring(claim.tax),
    ['X-Player']=claim.player,
    ['X-Transfer-Type'] = "Claim-Notice",
    ['X-Claim-Id'] = claim.id,
    ['X-Pool'] = POOL_ID,
    ['X-Ticker'] = SyncedInfo[DEFAULT_PAY_TOKEN_ID].Ticker,
    ['X-Denomination'] = SyncedInfo[DEFAULT_PAY_TOKEN_ID].Denomination,
    ['Pushed-For'] = claim.id,
  })
end
Handlers.add("claim",{
  Action = "Claim",
  From = function (_from) return _from ~= ao.id end,
  Owner = function (_owner) return _owner ~= Owner end,
},function(msg)
  assert(type(DEFAULT_PAY_TOKEN_ID) =="string" and #DEFAULT_PAY_TOKEN_ID==43,"missed payment token defination")
  local player = Players[msg.From]
  local _rate = SyncedInfo[POOL_ID]['Tax-Rate'] and tonumber(SyncedInfo[POOL_ID]['Tax-Rate']) or 0.4
  local _win_bal = player.win and player.win[1] or 0
  local _tax_bal = _win_bal * _rate
  if player.tax then
    _tax_bal = math.max(player.tax[1],_win_bal * _rate)
  end
  if _win_bal > 0 and _win_bal - _tax_bal >= 1 then
    local recipient = msg.From
    if msg.Recipient and #msg.Recipient == 43 then
      recipient = msg.Recipient
    end
    if not Claims then Claims = {} end
    local claim = {
      id = msg.Id,
      amount = _win_bal,
      tax = _tax_bal,
      quantity = math.floor(_win_bal-_tax_bal),
      recipient = recipient,
      player = msg.From
    }
    Claims[msg.Id] = claim
    utils.decrease(Players[msg.From].win,{claim.amount,0,-claim.amount})
    utils.decrease(Players[msg.From].tax,{claim.tax,0,-claim.tax})
    doClaim(claim)
  end
end)


-- archive & draw
Handlers.add("archive",{
  From = function (_from) return _from == POOL_ID end,
  Action = "Archive"
},function (msg)
  resetQuota()
  utils.increase(Stats,{total_archived_round = 1})
  msg.reply({
    Action = "Archived",
    Round = msg.Round,
    ['Archive-Id'] = msg.Id,
    Data = {
      minting = {
        quota = Quota,
        max_mint = MAX_MINT,
        minted = TotalSupply
      },
      token = {
        id = SyncedInfo[DEFAULT_PAY_TOKEN_ID].Id,
        ticker = SyncedInfo[DEFAULT_PAY_TOKEN_ID].Ticker,
        denomination = SyncedInfo[DEFAULT_PAY_TOKEN_ID].Denomination
      }
    }
  })
end)

Handlers.add("draw_notice",{
  From = function (_from) return _from == POOL_ID end,
  Action = "Draw-Notice"
},function (msg)
  -- do draw
  local draw = msg.Data
  local rewards = draw.rewards
  local tax_rate = draw.tax_rate or utils.toNumber(SyncedInfo[msg.From]['Tax-Rate'])
  local round = draw.round
  local lucky_number = draw.lucky_number
  local jackpot = draw.jackpot
  local archive = draw.archive
  local matched = draw.matched
  local reward_type = draw.reward_type
  local token = draw.token
  utils.increase(Stats,{
    total_reward_amount = jackpot,
    total_reward_count = 1,
    total_matched_draws = matched > 0 and 1 or 0,
    total_unmatched_draws = matched > 0 and 0 or 1,
  })
  utils.update(Stats,{
    ts_lastst_draw = msg.Timestamp,
  })

  for _uid,_prize in pairs(rewards) do
    if not Players[_uid].win then 
      Players[_uid].win = {0,0,0}
    end
    if not Players[_uid].tax then
      Players[_uid].tax = {0,0,0} 
    end
    if not Winners[_uid] then 
      Winners[_uid] = {0,0} -- count, amout
      utils.increase(Stats,{total_winners=1})
    end
    utils.increase(Players[_uid].win,{_prize,_prize,0})
    utils.increase(Winners[_uid],{1,_prize})
    local _tax = _prize * tax_rate
    utils.increase(Players[_uid].tax,{_tax,_tax,0})
    TopWinnings = TopWinnings or {}
    utils.updateRanking(TopWinnings,_uid,Players[_uid].win[2],50)
    local win_notice = {
      Target = _uid,
      Action = "Win-Notice",
      Prize = string.format("%.0f",_prize),
      Tax = tostring(_tax),
      Round = string.format("%.0f", round),
      Archive = archive,
      Token = token.id,
      Ticker = token.ticker,
      Denomination = token.denomination,
      Jackpot = string.format("%.0f", jackpot),
      ['Tax-Rate'] = tostring(tax_rate),
      ['Lucky-Number'] = tostring(lucky_number),
      ['Reward-Type'] = reward_type,
      Created = tostring(msg.timestamp),
      Data = Players[_uid]
    }
    Send(win_notice)
  end
  msg.reply({
    Action = "Draw-Result",
    Round = msg.Round,
    Archive = msg.Archive,
    ['Draw-Id'] = msg.Id,
    ['Content-Type'] = "text/html",
    Data = string.format([[
      <!DOCTYPE html> 
      <html>
        <head>
          <title>Aolotto Draw Result</title>
        </head>
        <body style="background:#DEC9FF;padding:1em; color:black;">
          <h1>Aolotto Draw Result</h1>
          <hr/>
          <ul>
            <li>ROUND: %s</li>
            <li>WINNERS: %s</li>
            <li>JACKPOT: %s</li>
            <li>LUCKY NUMBER: %s</li>
            <li>ARCHIVE: %s</li>
            <li>REWARD TOKEN: %s</li>
            <li>REWARD TYPE: %s</li>
          </ul>
          <hr/>
          <p><a href="https://aolotto.com">Aolotto</a> - <span>$1 onchain lottery only possible on AO</span><p>
        </body>
      </html>
    ]],msg.Round,msg.Winners,msg.Jackpot,msg['Lucky-Number'],msg.Archive,msg.Token,msg['Reward-Type'])
  })
end)


-- dividends
Handlers.add("distribute-dividends",{
  From = function (_from) return _from == POOL_ID end,
  Action = "Distribute-Dividends"
},function(msg)
  local dividends = utils.deepCopy(Stats.dividends)
  local fund = Funds[DEFAULT_PAY_TOKEN_ID]
  local _supply = utils.toNumber(TotalSupply)
  assert(fund >= dividends[1],"the actual token amount is less than the dividend amount")
  assert(_supply > 0, "no holders")
  local _unit = dividends[1] /  _supply
  local unpay = {}
  local _addresses = 0
  for uid, value in pairs(Balances) do
    if utils.toNumber(value) > 0 and uid ~= Owner then
      if not Players[uid] then Players[uid] = utils.deepCopy(initial_user) end
      _addresses = _addresses + 1
      local _amount = _unit * utils.toNumber(value)
      utils.increase(Players[uid].div,{_amount,_amount,0})
      utils.decrease(Stats.dividends,{_amount,0,-_amount})
      if Players[uid].div[1] >= 1000000 then
        unpay[uid] = math.floor(Players[uid].div[1])
      end
    end
  end

  utils.increase(Stats,{total_distributed=1})
  local no = tostring(Stats.total_distributed)
  msg.reply({
    Action = "Distributed-Dividends",
    Amount = tostring(dividends[1]),
    Addresses = tostring(_addresses),
    Supply = tostring(_supply),
    ['Distributed-No'] = no,
    Data = Stats.dividends
  })

  for _recipient, _qty in pairs(unpay) do
    Handlers.once("once_disributed_".._recipient.."_"..no,{
      From = DEFAULT_PAY_TOKEN_ID,
      Action = "Debit-Notice",
      ['X-Transfer-Type'] = "Distributed",
      ['X-Distributed-No'] = no,
      ['X-Supply'] = tostring(_supply),
      Recipient = _recipient,
      Quantity = string.format("%.0f",_qty)
    },function (msg)
      local _amount = utils.toNumber(msg.Quantity)
      utils.decrease(Players[msg.Recipient].div,{_amount,0,-_amount})
      Funds[msg.From] = Funds[msg.From] - _amount
    end)
    Send({
      Target = DEFAULT_PAY_TOKEN_ID,
      Action = "Transfer",
      Recipient = _recipient,
      Quantity = string.format("%.0f",_qty),
      ['X-Transfer-Type'] = "Distributed",
      ['X-Dividends-Total'] = tostring(dividends[1]),
      ['X-Addresses'] = tostring(_addresses),
      ['X-Supply'] = tostring(_supply),
      ['X-Distributed-No'] = no,
    })
  end
end)


