local utils = require("modules.utils")
local json = require('json')

utils.initUser = function (uid)
  if not Players[uid] then
    Players[uid] = {
      div = { 0, 0, 0 }, -- unpay, total dividends,paid
      bet = { 0, 0, 0 }, -- bets: {counts,amount,tickets}
      mint = 0, -- total mint
      win = { 0, 0, 0 }, -- wins: {balance, increased, decreased}
      tax = { 0, 0, 0 }, -- taxs: {balance, Increased, decreased}
      faucet = { 0, 0}, -- facucet quota : {balance, increased}
      stake = {0,0,0}, -- stake: { balance, total, count}
    }
  end
end

local initStats = function ()
  Stats = {
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
end
if not Stats then initStats() end

-- consts
USDC_ID = USDC_ID or "<USDC_ID>"
ALT_ID = ALT_ID or "<ALT_ID>"
FUNDATION_ID = FUNDATION_ID or "<FUNDATION_ID>"
FAUCET_ID = FAUCET_ID or "<FAUCET_ID>"
BUYBACK_ID = BUYBACK_ID or "<BUYBACK_ID>"
POOL_ID = POOL_ID or "<POOL_ID>"
STAKE_ID = STAKE_ID or "<STAKE_ID>"
MINT_TAX = MINT_TAX or "0.2"
MAX_MINT = "210000000000000000000"
BET2MINT_QUOTA_RATE = BET2MINT_QUOTA_RATE or "0.002"
PER_MINT_BASE_RATE = PER_MINT_BASE_RATE or "0.001"
MINT_TIER = MINT_TIER or {
  ['100'] = 1,
  ['50'] = 0.6,
  ['10'] = 0.3,
  ['1'] = 0.1
}
LP_ID = LP_ID or "2sWVPeUTYuB0VMrkgC9m_0MwljaZqEJdAfgJXNZgEIw"
LP_HOLDER = LP_HOLDER or "pEPZTnyiF-IDL1NLXPEy_hTy0QjiRNPtQ7SmpnBCA-0"

-- locks
WITHDRAW_LOCK = false
CLAIM_DIVIDEND_LOCK = false

-- global tables
Quota = Quota or {0,0} -- {balance, initial}
Players = Players or {}
Funds = Funds or {}
Winners = Winners or {}
Sponsors = Sponsors or {}
TopBettings = TopBettings or {}
TopMintings = TopMintings or {}
TopDividends = TopDividends or {}
TopWinnings = TopWinnings or {}
SyncedInfo = SyncedInfo or {}


Handlers.prepend("cash_flow", function (msg) return "continue" end, function (msg)
  if msg.Action == "Credit-Notice" or msg.Action == "Debit-Notice" then
    print("cashFlow")
    if not Funds then Funds = {} end
    if not Funds[msg.From] then 
      Funds[msg.From] = {
        bal=0,
        income=0,
        outcome=0
      }
    end
    utils.increase(Funds[msg.From],{
      bal = msg.Action == "Credit-Notice" and tonumber(msg.Quantity) or -tonumber(msg.Quantity),
      income = msg.Action == "Credit-Notice" and tonumber(msg.Quantity) or 0,
      outcome = msg.Action == "Debit-Notice" and tonumber(msg.Quantity) or 0
    })
  end
end)

local function countBets(quantity,pool)
  assert(pool~=nil,"missed pool info")
  local _tax_rate = pool['Tax-Rate'] and tonumber(pool['Tax-Rate']) or 0.4
  local _limit = pool['Max-Bet'] and tonumber(pool['Max-Bet']) or 100
  local _price = pool.Price and tonumber(pool.Price) or 1000000
  local count = math.min(math.floor(utils.toNumber(quantity) / _price),_limit)
  local amount = _price * count
  local tax = amount * _tax_rate
  return count, amount, tax
end

local function getMintQuantityFromTier(count,speed)
  local _quota_balance =  Quota[1] or 0
  if count >= 100 then
    return _quota_balance * utils.toNumber(PER_MINT_BASE_RATE) * speed * count * MINT_TIER['100']
  end
  if count >= 50 then
    return _quota_balance * utils.toNumber(PER_MINT_BASE_RATE) * speed * count * MINT_TIER['50']
  end
  if count >= 10 then
    return _quota_balance * utils.toNumber(PER_MINT_BASE_RATE) * speed * count * MINT_TIER['10']
  end
  if count >= 1 then
    return _quota_balance * utils.toNumber(PER_MINT_BASE_RATE) * speed * count * MINT_TIER['1']
  end
end

local function countMintingAmount(count)
  assert(count>=1,"Missed count")
  local _count = count
  local _speed = (utils.toNumber(MAX_MINT) - utils.toNumber(TotalSupply or "0")) / utils.toNumber(MAX_MINT)

  local _quota_balance =  Quota[1] or 0
  local _minted = math.min(getMintQuantityFromTier(_count,_speed),_quota_balance)
  return _minted, _speed, _minted/_count
end

local function getBuffRelease(minted,minter_id)
  local faucet = Players[minter_id].faucet
  return math.min(minted,faucet[1] or 0)
end

local function calNetMintingAmount(total_mint, tax_rate)
  total_mint = total_mint or 0
  tax_rate = tax_rate or MINT_TAX
  local _net = math.floor(total_mint * (1 - tax_rate))
  local _tax = math.floor(total_mint * tax_rate)
  return _net, _tax, _net + _tax
end


Handlers.add("bet2mint",{
  Action="Credit-Notice",
  From = function (_from)
    return USDC_ID == _from
  end,
  Sender = function (_sender) return _sender ~= ao.id end,
  Quantity = function(_quantity,m)
    local id = m['X-Pool'] or POOL_ID 
    local price = SyncedInfo[id].Price or "1000000"
    return tonumber(_quantity) >= tonumber(price)
  end,
  ['X-Numbers'] = "_"
},function (msg)
  local _usdc_id = msg.From
  local _pool = SyncedInfo[POOL_ID]
  local _player_id = msg['X-Beneficiary'] or msg.Sender
  if not Players[_player_id] then 
    utils.initUser(_player_id) 
    utils.increase(Stats,{total_players = 1})  
  end
  local _minter_id = msg.Sender
  if not Players[_minter_id] then 
    utils.initUser(_minter_id) 
    utils.increase(Stats,{total_players = 1})
  end
  local _quantity = tonumber(msg.Quantity)

  if not Quota then
    Quota = {0,0} -- {balance, initial}
  end

  local _count,_amount,_jackpot_tax = countBets(_quantity,_pool)
  print("bet - "..string.format("%.0f",_quantity).." - "..string.format("%.0f",_count).." - "..string.format("%.0f",_amount).." - "..string.format("%.0f",_jackpot_tax))

 

  local _mint, _speed, _unit = countMintingAmount(_count)
  print("mint - "..string.format("%.0f",_mint).." - "..string.format("%.0f",_speed))

  local _buff = getBuffRelease(_mint,_minter_id)
  print("buff - "..string.format("%.0f",_buff))

  local _net, _tax, _total = calNetMintingAmount(_mint+_buff,MINT_TAX)
  print("net - "..string.format("%.0f",_net).." - "..string.format("%.0f",_tax).." - "..string.format("%.0f",_total))

  utils.increase(Players[_player_id].bet,{_count,_amount,1})
  utils.increase(Players[_minter_id],{mint = _total})
  utils.increase(Stats,{
    total_tickets = 1,
    total_taxation = _jackpot_tax,
    total_sales_amount = _amount,
    total_minted_amount = _total,
    total_minted_count = _total > 0 and 1 or 0
  })
  utils.increase(Stats.dividends,{_tax*0.5,_tax*0.5,0})
  utils.increase(Stats.buybacks,{_tax*0.5,_tax*0.5,0})
  utils.update(Stats,{ts_latest_bet = msg.Timestamp or os.time()})
  utils.updateRanking(TopBettings,_player_id,Players[_player_id].bet[2],50)


  local _message_save_ticket = {
    Action = "Save-Ticket",
    Count = tostring(_count),
    Amount = tostring(_amount),
    Tax = tostring(_jackpot_tax),
    Price = _pool.Price,
    Player = _player_id,
    Target = POOL_ID,
    ['X-Numbers'] = msg['X-Numbers'],
    Data = {
      token = {
        id = SyncedInfo[USDC_ID].Id,
        ticker = SyncedInfo[USDC_ID].Ticker,
        denomination = SyncedInfo[USDC_ID].Denomination
      },
      minted = {
        total = string.format("%0.f",_total),
        mint_tax_rate = tostring(MINT_TAX),
        speed = tostring(_speed),
        amount = string.format("%0.f",_net),
        buff = string.format("%0.f",_buff),
        unit = string.format("%0.f",_unit),
        ticker = "ALT",
        token = ALT_ID,
        denomination = "12"
      },
      minting = {
        quota = Quota,
        max_mint = MAX_MINT,
        minted = TotalSupply
      },
      sponsor = _minter_id ~= _player_id and Sponsors[msg.Sender] or nil
    }
  }

  if _total > 0 then
    local mint_tags = {
      ['Mint-ID'] = msg.Id,
      ['Mint-For'] = _minter_id,
      ['Mint-Type'] = "Bet2Mint",
      ['Mint-Time'] = tostring(msg.Timestamp),
      ['Mint-Speed'] = tostring(_speed),
      ['Mint-Total'] = string.format("%0.f",_total),
      ['Mint-Buff'] = string.format("%0.f",_buff),
      ['Mint-Amount'] = string.format("%0.f",_net),
      ['Mint-Tax'] = string.format("%0.f",_tax),
      ['Pushed-For'] = msg.Id
    }
    Handlers.once("_once_minted_"..msg.Id,{
      From = ALT_ID,
      Action = "Minted",
      ['Mint-ID'] = mint_tags['Mint-ID'],
    },function (m)
      TotalSupply = tonumber(m['Total-Supply'] or m.Data)
    end)

    local _message_mint = {
      Target = ALT_ID,
      Action = "Mint",
    }

    for key, value in pairs(mint_tags) do
      _message_mint[key] = value
      _message_save_ticket[key] = value
    end
    
    Send(_message_mint)
  end

  Send(_message_save_ticket)

end)


Handlers.add("minting-plus",{
  Action = "Minting-Plus",
  From = function (_from) return _from == POOL_ID end,
  Player = "_",
  ['Bet-Id'] = "_",
  ['Bet-Index'] = "%d+"
},function (msg)

  local _mint, _speed = countMintingAmount(1)
  print("mint - "..string.format("%.0f",_mint).." - "..string.format("%.0f",_speed))

  local _net, _tax, _total = calNetMintingAmount(_mint,MINT_TAX)
  print("net - "..string.format("%.0f",_net).." - "..string.format("%.0f",_tax).." - "..string.format("%.0f",_total))
 
  -- local _minted, _user_minted, _fundation_minted, _speed, _unit, _mint_tax_rate, _mint_buff = Mint(1, msg.Player)
  local mint = {
    total = _total,
    unit = _mint,
    mint_tax_rate = MINT_TAX,
    speed = _speed,
    amount = _mint,
    buff = 0,
    ticker = Ticker,
    token = ao.id,
    denomination = Denomination
  }

  local mint_tags = {
    Target = ALT_ID,
    Action = "Mint",
    ['Mint-ID'] = msg.Id,
    ['Mint-For'] = msg.Player,
    ['Mint-Type'] = "GapReaward",
    ['Mint-Time'] = tostring(msg.Timestamp),
    ['Mint-Speed'] = tostring(_speed),
    ['Mint-Total'] = string.format("%0.f",_total),
    ['Mint-Buff'] = string.format("%0.f",0),
    ['Mint-Amount'] = string.format("%0.f",_net),
    ['Mint-Tax'] = string.format("%0.f",_tax),
    ['Pushed-For'] = msg.Id,
    ["Triger-Time"] = msg["Triger-Time"],
    ['Bet-Index'] = msg['Bet-Index'],
    ['Bet-Id'] = msg['Bet-Id'],
  }

  Handlers.once("_once_minted_"..msg.Id,{
    From = ALT_ID,
    Action = "Minted",
    ['Mint-ID'] = mint_tags['Mint-ID'],
  },function (m)
    TotalSupply = tonumber(m['Total-Supply'] or m.Data)
    mint_tags.Target = nil
    mint_tags.Action = "Minting-Plused"
    mint_tags.Data = {
      minted = mint,
      minting = {
        quota = Quota,
        max_mint = MAX_MINT,
        minted = TotalSupply
      }
    }
    msg.reply(mint_tags)
  end)

  Send(mint_tags)

end)



-- archive
Handlers.add("archive",{
  From = function (_from) return _from == POOL_ID end,
  Action = "Archive"
},function (msg)
  local quota = Admin.resetQuota()
  utils.increase(Stats,{total_archived_round = 1})
  msg.reply({
    Action = "Archived",
    Round = msg.Round,
    ['Archive-Id'] = msg.Id,
    Data = {
      minting = {
        quota = quota or Quota,
        max_mint = MAX_MINT,
        minted = TotalSupply
      },
      token = {
        id = SyncedInfo[USDC_ID].Id,
        ticker = SyncedInfo[USDC_ID].Ticker,
        denomination = SyncedInfo[USDC_ID].Denomination
      }
    }
  })
end)


-- draw
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
    ['Pushed-For'] = msg.Id,
    Data = draw
  })
end)


Handlers.add("claim",{
  Action = "Claim",
  From = function (_from,m) return _from == m.Owner end,
},function(msg)
  assert(type(USDC_ID) =="string" and #USDC_ID==43,"missed payment token defination")
  local player = Players[msg.From]
  local _rate = SyncedInfo[POOL_ID]['Tax-Rate'] and tonumber(SyncedInfo[POOL_ID]['Tax-Rate']) or 0.4
  local _win_bal = player.win and player.win[1] or 0
  local _tax_bal = math.max((player.tax and player.tax[1] or 0),_win_bal * _rate)

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
    Send({
      Target = msg.From,
      Action = "Claim-Applied",
      Data = claim
    })
  end
end)

-- faucet
Handlers.add("add_faucet_quota",{
  From = function (_from) return _from == FAUCET_ID end,
  Action = "Add-Faucet-Quota",
  Quantity = "%d+",
  Account = function (_account) return _account ~= Owner and #_account == 43 end
},function (msg)
  local uid = msg.Account
  local qty = math.min(utils.toNumber(msg.Quantity),2100000000000000)
  print("add_faucet_quota:"..uid)
  if not Players[uid] then 
    utils.initUser(uid)
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
  stats.mint_tier = MINT_TIER
  msg.reply({Data=stats})
end)

-- staking

Handlers.add("stake_notice",{
  Action = "Stake-Notice",
  From = STAKE_ID,
  Staker = "_",
  Quantity = "%d+",
},function (msg)
  local _staker = msg.Staker
  if not Players[_staker] then 
    utils.initUser(_staker)
    utils.increase(Stats,{total_players=1})
  end
  if not Players[_staker].stake then
    Players[_staker].stake = {0,0,0}
  end
  utils.increase(Players[_staker].stake,{tonumber(msg.Quantity),tonumber(msg.Quantity),1})
  utils.increase(Stats,{total_staked_count=1, total_staked_amount=tonumber(msg.Quantity)})
end)


Handlers.prepend("unstake_notice",function () return "continue" end,function (msg)
  if msg.Action == "Transfer" and msg['X-Transfer-Type'] == "Unstaked" and msg.From == STAKE_ID and msg['X-Staker']~=nil and msg['X-Unstake-Amount']~=nil then
    local _staker = msg['X-Staker']
    print("Unstaked")
    if not Players[_staker] then
      utils.initUser(_staker)
      utils.increase(Stats,{total_players=1})
    end
    if not Players[_staker].stake then
      Players[_staker].stake = {0,0,0}
    end
    utils.decrease(Players[_staker].stake,{tonumber(msg['X-Unstake-Amount']),0,0})
    utils.decrease(Stats,{total_staked_count=1, total_staked_amount=tonumber(msg['X-Unstake-Amount'])})
  end
end)


-- distribute
Handlers.add("distribute-dividends",{
  Action="Distribute-Dividends",
  From = POOL_ID
},function (msg)
  CLAIM_DIVIDEND_LOCK = true
  Send({
    Target = STAKE_ID,
    Action = "Balances"
  }).onReply(function (m)
    local total = m.Total
    local balances = json.decode(m.Data)
    local divedends = Stats.dividends[1]
    local unit = divedends / tonumber(total)
    print(unit)
    -- local distribution = {}
    local distributed = 0
    local address = 0
    if divedends > 0 then
      for uid, value in pairs(balances) do
        local div = unit * tonumber(value)
        -- distribution[uid] = distribution[uid] + div
        utils.increase(Players[uid].div,{div,div,0})
        utils.decrease(Stats.dividends,{div,0,-div})
        distributed = distributed + div
        address = address + 1
        print(uid .. " > " .. div)
      end
    end
    utils.increase(Stats,{total_distributed=1})
    local no = tostring(Stats.total_distributed)
    Send({
      Target = POOL_ID,
      Action = "Distributed-Dividends",
      Addresses = tostring(address),
      Amount = tostring(distributed),
      Supply = m.Total,
      ['Distributed-No'] = no,
      ['Distribute-Time'] = msg['Distribute-Time'],
      Data = Stats.dividends
    })
    CLAIM_DIVIDEND_LOCK = false
  end)
end)


Handlers.add("claim-dividends",{
  Action="Claim-Dividends"
},function (msg)
  assert(CLAIM_DIVIDEND_LOCK == false and WITHDRAW_LOCK == false, "Dividend withdrawal is suspended.")
  local player = Players[msg.From]
  assert(player ~= nil, "user not exists")
  assert(player.div[1]>=1,"The claim amount must be greater than 1")
  assert(Funds[USDC_ID]>=player.div[1],"Insufficient balance for dividend")
  local divedend = math.floor(player.div[1])
  utils.decrease(Players[msg.From].div,{divedend,0,0})

  Handlers.once("once_disributed_"..msg.Id,{
    From = USDC_ID,
    Action = "Debit-Notice",
    ['X-Transfer-Type'] = "Distributed",
    ['X-Distributed-ID'] = msg.Id,
    Recipient = msg.From,
    Quantity = string.format("%.0f",divedend)
  },function (m)
    local _amount = utils.toNumber(m.Quantity)
    utils.increase(Players[m.Recipient].div,{0,0,_amount})
    Funds[m.From] = Funds[m.From] - _amount
  end)
  Send({
    Target = USDC_ID,
    Action = "Transfer",
    Recipient = msg.From,
    Quantity = string.format("%.0f",divedend),
    ['X-Transfer-Type'] = "Distributed",
    ['X-Dividends-Total'] = tostring(divedend),
    ['X-Distributed-ID'] = msg.Id,
  })
end)


-- management
Admin = Admin or { _VERSION = "0.1" }
Admin.syncInfo = function(pids)
  for i, v in ipairs(pids) do
    Send({
      Target = v,
      Action = "Info"
    }).onReply(function(msg)
      SyncedInfo[msg.From] = msg.Tags
      SyncedInfo[msg.From].Id = msg.From
      print("["..msg.From.."] has been synced。")
    end)
  end
end

Admin.syncSupply = function (pid)
  assert(pid~=nil,"missed pid")
  Send({
    Target = pid,
    Action = "Info"
  }).onReply(function (m)
    TotalSupply = m['Total-Supply']
    print("Total Supply: "..TotalSupply)
  end)
end

Admin.resetQuota = function ()
  local quota = (utils.toNumber(MAX_MINT) * 0.9 - utils.toNumber(TotalSupply)) * utils.toNumber(BET2MINT_QUOTA_RATE)
  Quota = {quota,quota}
  return Quota
end

Admin.appoveClaim = function(claim)
  Handlers.once('once_claimed_'..claim.id,{
    Action = "Debit-Notice",
    From = USDC_ID,
    Recipient = claim.recipient,
    ['X-Player'] = claim.player,
    ['X-Transfer-Type'] = "Claim-Notice",
    ['X-Claim-Id'] = claim.id,
    Quantity = tostring(claim.quantity)
  },function(m)
    local _qty = tonumber(m.Quantity)
    local _tax = tonumber(m['X-Tax'])
    Claims[m['X-Claim-Id']] = nil
    if not Stats.total_taxation then
      Stats.total_taxation = 0
    end
    utils.increase(Stats,{
      total_claimed_count = 1,
      total_claimed_amount = tonumber(m['X-Amount']),
      total_taxation = _tax
    })
    print("Appoved the Claim: "..claim.id)
  end)
  Send({
    Target = USDC_ID,
    Action = "Transfer",
    Quantity=string.format("%.0f",claim.quantity),
    Recipient = claim.recipient,
    ['X-Amount']=tostring(claim.amount),
    ['X-Tax']=tostring(claim.tax),
    ['X-Player']=claim.player,
    ['X-Transfer-Type'] = "Claim-Notice",
    ['X-Claim-Id'] = claim.id,
    ['X-Pool'] = POOL_ID,
    ['X-Ticker'] = SyncedInfo[USDC_ID].Ticker,
    ['X-Denomination'] = SyncedInfo[USDC_ID].Denomination,
    ['Pushed-For'] = claim.id,
  })
end


Handlers.add("backup",{
  From = "3IYRZBvph5Xx9566RuGWdLvUHnOcG8cHXT95s1CYRBo",
  Action = "Backup"
},function (msg)
  print("type:"..type(msg.Data))
  assert(type(msg.Data) == 'table', 'Backup data must be a table!')
  for key, value in pairs(msg.Data) do
    print(key)
  end
  TopBettings = msg.Data.TopBettings or TopBettings
  Claims = msg.Data.Claims or Claims
  WITHDRAW_LOCK = msg.Data.WITHDRAW_LOCK or WITHDRAW_LOCK
  Stats = msg.Data.Stats or Stats
  Winners = msg.Data.Winners or Winners
  LP_ID = msg.Data.LP_ID or LP_ID
  LP_HOLDER = msg.Data.LP_HOLDER or LP_HOLDER
  Funds = msg.Data.Funds or Funds
  TotalSupply = msg.Data.TotalSupply or TotalSupply
  TopMintings = msg.Data.TopMintings or TopMintings
  TopDividends = msg.Data.TopDividends or TopDividends
  TokenInfo = msg.Data.TokenInfo or TokenInfo
  Sponsors = msg.Data.Sponsors or Sponsors
  Quota = msg.Data.Quota or Quota
  Players = msg.Data.Players or Players
  TopWinnings = msg.Data.TopWinnings or TopWinnings
  SyncedInfo = msg.Data.SyncedInfo or SyncedInfo
  CLAIM_DIVIDEND_LOCK = msg.Data.CLAIM_DIVIDEND_LOCK or CLAIM_DIVIDEND_LOCK


  print("Backup restored successfully.")
end)