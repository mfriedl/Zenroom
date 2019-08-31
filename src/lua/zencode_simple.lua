-- This file is part of Zenroom (https://zenroom.dyne.org)
--
-- Copyright (C) 2018-2019 Dyne.org foundation
-- designed, written and maintained by Denis Roio <jaromil@dyne.org>
--
-- This program is free software: you can redistribute it and/or modify
-- it under the terms of the GNU Affero General Public License as
-- published by the Free Software Foundation, either version 3 of the
-- License, or (at your option) any later version.
--
-- This program is distributed in the hope that it will be useful,
-- but WITHOUT ANY WARRANTY; without even the implied warranty of
-- MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
-- GNU Affero General Public License for more details.
--
-- You should have received a copy of the GNU Affero General Public License
-- along with this program.  If not, see <https://www.gnu.org/licenses/>.

-- make sure relevant defaults are there
CONF.curve = CONF.curve or 'goldilocks'
CONF.encoding = CONF.encoding or url64
CONF.encoding_prefix = CONF.encoding_prefix or 'u64'

local _ecdh = ECDH.new(CONF.curve) -- used for validation

ZEN.add_schema({
	  -- keypair (ECDH)
	  public_key = function(obj)
		 local o = obj.public_key or obj -- fix recursive schema check
		 if type(o) == "string" then o = ZEN:convert(o) end
		 ZEN.assert(_ecdh:checkpub(o),
					"Public key is not a valid point on curve: "..CONF.curve)
		 return o
	  end,
      keypair = function(obj)
         return { public_key  = ZEN:validate_recur(obj, 'public_key'),
                  private_key = ZEN.get(obj, 'private_key') }
	  end,
	  secret_message = function(obj)
		 return { checksum = ZEN.get(obj, 'checksum'),
				  header   = ZEN.get(obj, 'header'),
				  iv       = ZEN.get(obj, 'iv'),
				  message  = ZEN.get(obj, 'message'),
				  pubkey   = ZEN.get(obj, 'pubkey'),
				  scenario = ZEN.get(obj, 'scenario', str),
				  zenroom  = ZEN.get(obj, 'zenroom', str),
				  curve    = ZEN.get(obj, 'curve', str) }
	  end,
	  signed_message = function(obj)
		 return { r = ZEN.get(obj, 'r'),
				  s = ZEN.get(obj, 's'),
				  text = ZEN.get(obj, 'text', str),
				  scenario = ZEN.get(obj, 'scenario', str),
				  zenroom  = ZEN.get(obj, 'zenroom', str),
				  curve    = ZEN.get(obj, 'curve', str) }
	  end
})

-- generate keypair
local function f_keygen()
   local kp
   local ecdh = ECDH.new(CONF.curve)
   kp = ecdh:keygen()
   ZEN:pick('keypair', { public_key = kp.public,
						 private_key = kp.private })
   ZEN:validate('keypair')
   ZEN:ack('keypair')
end
When("I create my new keypair", f_keygen)
When("I generate my keys", f_keygen)

-- encrypt to a single public key
When("I encrypt the '' to '' for ''", function(what, msg, recpt)
		ZEN.assert(ACK.keypair, "Keyring not found")
		ZEN.assert(ACK.keypair.private_key, "Private key not found in keyring")
		ZEN.assert(ACK[what], "Data to encrypt not found in "..what)
		local from = ECDH.new(CONF.curve)
		from:private(ACK.keypair.private_key)
		local to = ECDH.new(CONF.curve)
		ZEN.assert(ACK[recpt], "Public key not found")
		to:public(ACK[recpt])
		ACK[msg] = from:encrypt(to, ACK[what], str('empty'))
		-- include contextual information
		ACK[msg].zenroom = VERSION.original
		ACK[msg].curve = CONF.curve
		ACK[msg].scenario = ZEN.scenario
end)

When("I decrypt the '' to ''", function(src,dst)
		ZEN.assert(ACK.keypair, "Keyring not found")
		ZEN.assert(ACK.keypair.private_key, "Private key not found in keyring")
		ZEN.assert(ACK[src], "Ciphertext not found")
		if VERSION.original ~= ACK[src].zenroom:str() then
		   warn("Ciphertext was not produced with running version of Zenroom: "
				   ..ACK[src].zenroom:str().. " (running "..VERSION.original..")")
		end
		local recpt = ECDH.new(ACK[src].curve:str() or CONF.curve)
		recpt:private(ACK.keypair.private_key)
		ACK[dst] = recpt:decrypt(ACK[src])
end)

-- sign a message and verify
When("I sign the draft as ''", function(dst)
		ZEN.assert(ACK.keypair, "Keyring not found")
		ZEN.assert(ACK.keypair.private_key, "Private key not found in keyring")
		local dsa = ECDH.new(CONF.curve)
		dsa:private(ACK.keypair.private_key)
		ACK[dst] = dsa:sign(ACK.draft)
		-- include contextual information
		ACK[dst].text = ACK.draft:string()
		ACK[dst].zenroom = VERSION.original
		ACK[dst].curve = CONF.curve
		ACK[dst].scenario = ZEN.scenario
end)

When("I verify the '' is authentic", function(msg)
		ZEN.assert(ACK.public_key, "Public key not found")
		local dsa = ECDH.new(CONF.curve)
		dsa:public(ACK.public_key)
		local sm = ACK[msg]
		ZEN.assert(sm, "Signed message not found: "..msg)
		ZEN.assert(dsa:verify(sm.text,{ r = sm.r, s = sm.s }),
				   "The signature is not authentic")
end)