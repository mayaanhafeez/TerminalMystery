-- test/test_solve.lua — canonical-solve regression through the headless engine.
--
-- Replays the documented winning path (CLAUDE.md "Mystery Solution") end to
-- end: FOXGLOVE cipher -> the mod-8 recipe -> chmod 765 unlocks the Server
-- Room -> diff/sed restores Daniel's scrubbed handle -> the mv-gated Wine
-- Cellar -> accuse lin. Doubles as the wiring check for headless/engine.lua.

local T = require("test.runner")
local Engine = require("headless.engine")

T.suite("Canonical solve (headless engine)")

T.test("full documented path wins via accuse lin", function()
    local session = Engine.Session.new(1)

    local function run(cmd)
        local output, meta = session:run(cmd)
        T.ok(output ~= nil, "command errored: " .. cmd .. "\n  " .. tostring(meta and meta.error))
        return output, meta
    end

    -- Entrance Hall
    run("ls -a")
    run("cat welcome.txt")
    run("cat guest_list.txt")
    run("cat slack_general.txt")
    run("cat .personnel_dossier.txt")

    -- Home Office: the cipher and the decode recipe
    run("cd home_office")
    local cipher = run("cat .cipher_note.txt")
    T.ok(cipher:find("IRAJORYH"), "expected the ciphertext in cipher_note.txt")
    run("cat draft_email.txt")
    run("cat repo_log.txt")
    run("cat slack_eng_help.txt")
    local dm = run("cat slack_trent_dm.txt")
    T.ok(dm:find("FOXGLOVE"), "expected the vault word in slack_trent_dm.txt")

    -- FOXGLOVE, a=1..z=26 mod 8: F6 O7 X0 G7 L4 O7 V6 E5
    -- repeated letter (O, mod8=7) + first (^F, mod8=6) + last (E$, mod8=5, odd->keep) = 765
    run("cd ..")
    local locked = run("cd server_room")
    T.ok(locked:find("Permission denied"), "server room should still be locked")
    local wrong = run("chmod 000 server_room")
    T.ok(wrong:find("incorrect code"), "wrong code should be rejected")
    local unlocked = run("chmod 765 server_room")
    T.ok(unlocked:find("765"), "chmod should report the new mode")

    -- Server Room: diff exposes the cut clause, sed restores dlin
    run("cd server_room")
    run("ls -a")
    run("cat billing_audit.txt")
    run("cat slack_final.txt")
    run("cat .slack_draft.txt")
    local diffed = run("diff .slack_draft.txt slack_final.txt")
    T.ok(diffed:find("cellar"), "diff should surface the cut cellar clause")
    run("chmod +w audit_stream.log")
    local sedded = run("sed -i 's/svc-agent/dlin/g' audit_stream.log")
    T.ok(sedded:find("edited"), "sed -i should report a successful edit")

    -- Sunroom -> mv-gated Wine Cellar
    run("cd ..")
    run("cd sunroom")
    run("cat keycard.txt")
    run("cd ..")
    local denied = run("cd cellar")
    T.ok(denied:find("badge"), "cellar should still be locked without the keycard")
    run("mv sunroom/keycard.txt .")
    run("cd cellar")
    run("cat badge.txt")
    local log = run("cat cellar_access_log.txt")
    T.ok(log:find("dlin"), "cellar access log should show Daniel's badge scan")

    run("cd ..")
    local _, meta = run("accuse lin")
    T.ok(meta.won, "accuse lin should win the game")
    T.ok(meta.elapsed ~= nil and meta.elapsed >= 0, "win_time should be a non-negative elapsed value")
end)
