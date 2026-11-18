function Initialize()
  mPct = SKIN:GetMeasure('MesureBatterie')
  mSecteur = SKIN:GetMeasure('MesureSecteur')
end

function Update()
  if SKIN:GetVariable('CURRENTCONFIGY') ~= '0' or SKIN:GetVariable('CURRENTCONFIGX') ~= '0' then SKIN:Bang('!Move', '0', '0') end
  local p = mPct:GetValue() or 0
  local secteur = mSecteur:GetValue() or 0
  local eco = tonumber(SKIN:GetVariable('Economie')) or 0
  local charge = tonumber(SKIN:GetVariable('EnCharge')) or 0
  local blanc, vert, jaune, rouge, sombre = '255,255,255,255', '52,199,89,255', '255,214,10,255', '255,69,58,255', '18,14,30,255'
  local couleur, info, texte = blanc, '#InfoNormal#', blanc
  local eFond, eBord = '0,0,0,0', '0,0,0,0'
  if secteur == 1 and charge == 1 then
    couleur, info = vert, '#InfoCharge#'
    eFond, eBord = blanc, sombre
  elseif secteur == 1 then
    couleur, info = blanc, '#InfoPause#'
    eFond, eBord = sombre, blanc
  elseif p < 20 then
    couleur = rouge
  elseif eco == 1 then
    couleur, info, texte = jaune, '#InfoEco#', jaune
  end
  if eco == 1 and secteur == 1 then texte = jaune end
  -- rien n'a change depuis la derniere seconde : on ne redessine pas (economise le processeur)
  local cle = couleur .. info .. texte .. eFond .. math.floor(p)
  if cle == derniereCle then return '' end
  derniereCle = cle
  SKIN:Bang('!SetVariable', 'CoulBat', couleur)
  SKIN:Bang('!SetVariable', 'InfoBat', info)
  SKIN:Bang('!SetVariable', 'EclairFond', eFond)
  SKIN:Bang('!SetVariable', 'EclairBord', eBord)
  SKIN:Bang('!SetOption', 'BatteriePct', 'FontColor', texte)
  SKIN:Bang('!SetOption', 'BatteriePct', 'ToolTipText', info)
  SKIN:Bang('!UpdateMeter', 'BatterieIcone')
  SKIN:Bang('!UpdateMeter', 'BatteriePct')
  return ''
end