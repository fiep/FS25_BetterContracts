--=======================================================================================================
-- BetterContracts SCRIPT
--
-- Purpose:		Enhance ingame contracts menu.
-- Author:		Mmtrx
-- Changelog:
--  v1.1.0.0    08.01.2025  UI settings page, discount mode
--  v1.1.1.1    04.02.2025  fix white UI page (#19, #24, #29). Fix server save/load #22, #27, #30.
-- 							fix ContractBoost compat #28
--=======================================================================================================
SettingsManager = {}
local SettingsManager_mt = Class(SettingsManager, TabbedMenuFrameElement)

function SettingsManager.new(target, custom_mt)
	local self = GuiElement.new(target, custom_mt or SettingsManager_mt)
	self.settings = {}  		-- list of all setting objects 
	self.settingsByName = {}  	-- contains setting objects by name 
	self.controls = {}
	return self
end
function InGameMenuSettingsFrame:showSettings()
	-- callback for mod page tabs button
	-- set the multitext to corresponding state
	local modState = BetterContracts.settingsMgr.modState
	if modState == nil then 
		Logging.error("onClick BetterContracts: modState is nil")
		return
	end
	self.subCategoryPaging:setState(modState, true)
end
--[[
function InGameMenuSettingsFrame:onClickControls()
	-- set to last but one state
	self.subCategoryPaging:setState(#self.subCategoryPaging.texts -1, true)
end
]]
function SettingsManager:insertSettingsPage()
  -- make additional subCategory tab button  
	local pageSettings = g_inGameMenu.pageSettings
	local modButton = pageSettings.subCategoryTabs[1]:clone(pageSettings.subCategoryBox)
	modButton.textUpperCase = false
	modButton:setText("BetterContracts")
	modButton.onClickCallback = InGameMenuSettingsFrame.showSettings

	-- our button / page is the last in the list
	table.insert(pageSettings.subCategoryTabs, modButton) 

	self.modPageNr = #pageSettings.subCategoryTabs   -- until now: always 6

	pageSettings.subCategoryPaging:addText(self.modPageNr)
	pageSettings.subCategoryBox:invalidateLayout()

	debugPrint("**insertSettingsPage subCategoryTabs:")
	if BetterContracts.config.debug then
		for i=1,#pageSettings.subCategoryTabs do
			printf("%d %s",i, pageSettings.subCategoryTabs[i].text)
		end
	end

  -- make additional subCategory page  
	local modPage = pageSettings.subCategoryPages[1]:clone(pageSettings)

	table.insert(pageSettings.subCategoryPages, modPage)
	modPage.id = "bcPage"
	modPage.settingsLayout =
		modPage:getFirstDescendant(function(elem) 
		return elem.profile == "fs25_settingsLayout" 
		end) 
	modPage.noPermission = 		
		modPage:getFirstDescendant(function(elem) 
		return elem.profile == "fs25_settingsNoPermissionText" 
		end) 

	modPage.settingsLayout.id = "settingsLayout"
	modPage.settingsLayout.scrollDirection = "vertical"
	modPage.noPermission:setVisible(false)

	-- remove inner controls
	for i = #modPage.settingsLayout.elements,1,-1 do
		modPage.settingsLayout.elements[i]:delete()
	end
	--UIHelper.updateFocusIds(modPage)
	
	return modPage, modButton
end
function SettingsManager:init()
	local bc = BetterContracts
	-- clone from generalSettings: id="subCategoryPages[1]":
	local modPage, modButton = self:insertSettingsPage()
	bc.modPage = modPage
	
	-- dynamically generate our gui elements for settings page
	UIHelper.createControlsDynamically(modPage, self, ControlProperties, "bc_")
	UIHelper.setupAutoBindControls(self, bc.config, SettingsManager.onSettingsChange)  

	self.populateAutoBindControls() 			-- Apply initial values	
	self.refreshMP:setVisible(g_currentMission.missionDynamicInfo.isMultiplayer)

	 -- make controls in development invisible:
	for _, name in ipairs(ControlDevelop) do
		self[name]:setVisible(bc.config.debug)
		if ControlDep[name] then 
			for _, nam in ipairs(ControlDep[name]) do
				self[nam]:setVisible(bc.config.debug)
			end
		end
	end
	-- Update the focus manager:
	local currentGui = FocusManager.currentGui
	FocusManager:setGui(bc.frSet.name)
	FocusManager:removeElement(modPage)
	FocusManager:removeElement(modButton) -- if we made our tab button from a gui.xml
	FocusManager:loadElementFromCustomValues(modPage)
	FocusManager:loadElementFromCustomValues(modButton)
	FocusManager:setGui(currentGui)

	modPage.settingsLayout:invalidateLayout()	

	-- set our header info, to be picked up in updateSubCategoryPages()
	InGameMenuSettingsFrame.SUB_CATEGORY.BCONTRACTS = self.modPageNr
	InGameMenuSettingsFrame.HEADER_SLICES[InGameMenuSettingsFrame.SUB_CATEGORY.BCONTRACTS] = 
		"gui.icon_ingameMenu_contracts"
	InGameMenuSettingsFrame.HEADER_TITLES[InGameMenuSettingsFrame.SUB_CATEGORY.BCONTRACTS] = 
		"bc_name"

	-- adjust settings for our menu page when it is selected:
	Utility.appendedFunction(bc.frSet,"onFrameOpen", onSettingsFrameOpen)
	Utility.overwrittenFunction(bc.frSet.subCategoryPaging, 
		"onClickCallback", updateSubCategoryPages) 		-- subCategoryPaging callback

	debugPrint("** SettingsManager:initiated")
end
function onSettingsFrameOpen(self)
	-- appended to InGameMenuSettingsFrame:onFrameOpen()
	debugPrint("**onSettingsFrameOpen()")
	self.isOpening = true
	local bc = BetterContracts
	local modPage = bc.modPage
	local settingsPage = bc.settingsMgr
	local isMultiplayer = g_currentMission.missionDynamicInfo.isMultiplayer

	-- our mod button should always be the last one in subCategoryPaging MTO
	settingsPage.modState = #g_inGameMenu.pageSettings.subCategoryPaging.texts

	if isMultiplayer and not (g_inGameMenu.isServer or g_inGameMenu.isMasterUser) then  
		modPage.settingsLayout:setVisible(false)
		modPage.noPermission:setVisible(true)
	else
		modPage.settingsLayout:setVisible(true)
		modPage.noPermission:setVisible(false)

		if settingsPage.populateAutoBindControls then 
		  -- Note: This method is created dynamically by UIHelper.setupAutoBindControls
			settingsPage.populateAutoBindControls() 
		end
		-- apply initial disabled states
		settingsPage:updateDisabled("lazyNPC")				
		settingsPage:updateDisabled("discountMode")			
		settingsPage:updateDisabled("hardMode")

		if bc.contractBoost then 
		-- disable if ContractBoost.settings.enableContractValueOverrides is on
			 local disabled = g_currentMission.contractBoostSettings.enableContractValueOverrides
			 settingsPage.rewardMultiplier.setting:updateDisabled(disabled)
			 settingsPage.rewardMultiplierMow.setting:updateDisabled(disabled)
		end	
		--  make alternating backgrounds
		modPage:setVisible(true)
		self:updateAlternatingElements(modPage.settingsLayout)
	end
	self.isOpening = false
end
function updateSubCategoryPages(self, superf, state)
	-- overwrites InGameMenuSettingsFrame:updateSubCategoryPages() 
	debugPrint("**updateSubCategoryPages state = %d", state)
	local modPage = BetterContracts.modPage
	local retValue = superf(self, state)
	--local retValue = modPage.updateSubCategoryPages(self, state)

	local val = self.subCategoryPaging.texts[state]
	if val ~= nil and tonumber(val) == InGameMenuSettingsFrame.SUB_CATEGORY.BCONTRACTS then
		self.settingsSlider:setDataElement(modPage.settingsLayout)
		FocusManager:linkElements(self.subCategoryPaging, FocusManager.TOP, 
			modPage.settingsLayout.elements[#modPage.settingsLayout.elements].elements[1])
		FocusManager:linkElements(self.subCategoryPaging, FocusManager.BOTTOM, 
			modPage.settingsLayout:findFirstFocusable(true))
	end
	return retValue
end
function SettingsManager:updateDisabled(controlName)
	-- set disabled states for dependent controls
	 local disabled = self[controlName].elements[1]:getState() == 1
	 for _, nam in ipairs(ControlDep[controlName]) do
		self[nam].setting:updateDisabled(disabled)
	 end
end
function SettingsManager:setGeneration(setting)
	-- body
	local bc = BetterContracts
	if setting.name == "generationInterval" then 
		bc:updateGenerationInterval()
		return
	end
	local nam = setting.name:sub(4)
	-- update excluded contracts
	if TableUtility.contains({"Tree","Dead","Rock"}, nam) then 
		bc.noContracts.treeTransportMission = bc.config.genTree 
		bc.noContracts.deadwoodMission = bc.config.genDead 
		bc.noContracts.destructibleRockMission = bc.config.genRock
		return
	end
	-- update excluded harvest contracts
	bc.canHarvest.GRAIN = bc.config.genGrain
	bc.canHarvest.GREEN = bc.config.genGreen
	bc.canHarvest.VEGETABLES = bc.config.genVegetable
	bc.canHarvest.ROOT = bc.config.genRoot
end
function SettingsManager:onSettingsChange(control, newValue) 
	-- called by the controls onClick callback. Callback has already set the corresponding
	-- bc.config value on client who changed it
	local bc = BetterContracts
	 local setting = control.setting

	 -- disable dependent settings if needed
	 if setting.name == "lazyNPC" then  
		for _, nam in ipairs(ControlDep.lazyNPC) do
			self[nam].setting:updateDisabled(not newValue)
		end
	 elseif setting.name == "discountMode" then  
		for _, nam in ipairs(ControlDep.discountMode) do
			self[nam].setting:updateDisabled(not newValue)
		end
		-- adjust map context farmland box:
		bc:discountVisible(newValue)

	 elseif setting.name == "hardMode" then 
		for _, nam in ipairs(ControlDep.hardMode) do
			self[nam].setting:updateDisabled(not newValue)
		end
	 elseif setting.name == "toDeliver" then 
		HarvestMission.SUCCESS_FACTOR = newValue

	 elseif setting.name:sub(1,3) == "gen" then 
		self:setGeneration(setting)
	 end	

	 SettingsEvent.sendEvent(setting)
end
