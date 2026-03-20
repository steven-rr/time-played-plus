local _, TPP = ...

TPP.Options = {}

local Options = TPP.Options

function Options.GetOptionsTable()
    return {
        name = "TimePlayed+",
        type = "group",
        args = {
            scale = {
                type = "range",
                name = "UI Scale",
                desc = "Scale all TimePlayed+ frames",
                min = 0.5,
                max = 1.5,
                step = 0.05,
                order = 1,
                get = function() return TPP.db.profile.scale end,
                set = function(_, value)
                    TPP.db.profile.scale = value
                    TPP.Utils.ApplyScale(value)
                end,
            },
            minimap = {
                type = "toggle",
                name = "Show Minimap Button",
                desc = "Toggle the minimap button visibility",
                order = 2,
                get = function() return not TPP.db.profile.minimap.hide end,
                set = function(_, value)
                    TPP.db.profile.minimap.hide = not value
                    if value then
                        LibStub("LibDBIcon-1.0"):Show("TimePlayed+")
                    else
                        LibStub("LibDBIcon-1.0"):Hide("TimePlayed+")
                    end
                end,
            },
            dataSpacer = {
                type = "header",
                name = "Data",
                order = 10,
            },
            deleteHistory = {
                type = "execute",
                name = "Delete All Session History",
                desc = "Permanently delete all recorded sessions for every character",
                order = 11,
                confirm = true,
                confirmText = "Are you sure? This will delete all session history for ALL characters and cannot be undone.",
                func = function()
                    TPP.db.global.sessions = {}
                    if TPP.HistoryUI.Refresh then TPP.HistoryUI.Refresh() end
                    if TPP.StatsUI.Refresh then TPP.StatsUI.Refresh() end
                    print("|cffffd100TimePlayed+|r: Session history cleared.")
                end,
            },
        },
    }
end

function Options.Setup()
    local AceConfig = LibStub("AceConfig-3.0")
    local AceConfigDialog = LibStub("AceConfigDialog-3.0")

    AceConfig:RegisterOptionsTable("TimePlayed+", Options.GetOptionsTable())
    Options.categoryID = AceConfigDialog:AddToBlizOptions("TimePlayed+", "TimePlayed+")
end

function Options.Open()
    Settings.OpenToCategory(Options.categoryID.name)
end
