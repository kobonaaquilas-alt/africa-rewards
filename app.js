// AfriReach — client application. Only the public publishable key is used here.
const SUPABASE_URL = "https://jdzseeodhdzbqvvubtnw.supabase.co";
const SUPABASE_PUBLISHABLE_KEY = "sb_publishable_Rl-SRvW-5gH5T61xuGLg1w_lwD6qRxd";
const db = window.supabase?.createClient(SUPABASE_URL, SUPABASE_PUBLISHABLE_KEY);

const menuToggle = document.getElementById("menuToggle");
const nav = document.getElementById("mainNav");
menuToggle?.addEventListener("click", () => {
  const open = nav.classList.toggle("open");
  menuToggle.setAttribute("aria-expanded", String(open));
  menuToggle.textContent = open ? "×" : "☰";
});
nav?.querySelectorAll("a").forEach(a => a.addEventListener("click", () => {
  nav.classList.remove("open");
  menuToggle?.setAttribute("aria-expanded", "false");
  if (menuToggle) menuToggle.textContent = "☰";
}));
document.getElementById("year").textContent = new Date().getFullYear();

const $ = id => document.getElementById(id);
const escapeHtml = value => String(value ?? "").replace(/[&<>"']/g, c => ({
  "&":"&amp;","<":"&lt;",">":"&gt;",'"':"&quot;","'":"&#39;"
}[c]));
const money = value => new Intl.NumberFormat("fr-FR", {maximumFractionDigits:0}).format(Number(value || 0)) + " XOF";
let authMode = "signup";
let currentUser = null;
let currentProfile = null;

function showMessage(id, message, error = false) {
  const el = $(id);
  if (!el) return;
  el.textContent = message;
  el.classList.toggle("is-error", error);
  el.classList.toggle("is-success", !error);
}

function setAuthMode(mode) {
  authMode = mode;
  document.querySelectorAll(".auth-tab").forEach(tab => tab.classList.toggle("active", tab.dataset.mode === mode));
  $("signupFields").hidden = mode !== "signup";
  $("authName").required = mode === "signup";
  $("authRole").required = mode === "signup";
  $("authCountry").required = mode === "signup";
  $("authPassword").autocomplete = mode === "signup" ? "new-password" : "current-password";
  $("authSubmit").innerHTML = mode === "signup" ? 'Créer mon compte <span>→</span>' : 'Me connecter <span>→</span>';
  showMessage("authMessage", mode === "signup"
    ? "Créez votre compte participant ou créateur."
    : "Connectez-vous à votre espace AfriReach.");
}
document.querySelectorAll(".auth-tab").forEach(tab => tab.addEventListener("click", () => setAuthMode(tab.dataset.mode)));

async function handleAuth(event) {
  event.preventDefault();
  if (!db) return showMessage("authMessage", "Connexion au service indisponible. Rechargez la page.", true);
  const form = new FormData(event.currentTarget);
  const email = String(form.get("email") || "").trim().toLowerCase();
  const password = String(form.get("password") || "");
  const button = $("authSubmit");
  button.disabled = true;
  button.textContent = "Veuillez patienter…";
  try {
    if (authMode === "signup") {
      const {data, error} = await db.auth.signUp({
        email, password,
        options: {emailRedirectTo: window.location.origin, data: {
          display_name: String(form.get("display_name") || "").trim(),
          account_type: form.get("account_type") === "creator" ? "creator" : "participant",
          country: String(form.get("country") || "Togo")
        }}
      });
      if (error) throw error;
      if (data.session) {
        showMessage("authMessage", "Compte créé. Ouverture de votre espace…");
        await loadMemberArea();
      } else {
        showMessage("authMessage", "Compte créé. Vérifiez votre boîte e-mail pour confirmer votre adresse, puis connectez-vous.");
        setAuthMode("signin");
      }
    } else {
      const {error} = await db.auth.signInWithPassword({email, password});
      if (error) throw error;
      showMessage("authMessage", "Connexion réussie.");
      await loadMemberArea();
    }
  } catch (error) {
    showMessage("authMessage", error.message || "Une erreur est survenue.", true);
  } finally {
    button.disabled = false;
    button.innerHTML = authMode === "signup" ? 'Créer mon compte <span>→</span>' : 'Me connecter <span>→</span>';
  }
}
$("authForm")?.addEventListener("submit", handleAuth);

async function loadMemberArea() {
  if (!db) return;
  const {data:{user}} = await db.auth.getUser();
  currentUser = user;
  if (!user) {
    $("authCard").hidden = false;
    $("memberDashboard").hidden = true;
    return;
  }
  const {data:profile, error} = await db.from("profiles").select("id,display_name,country,account_type").eq("id", user.id).single();
  if (error) {
    showMessage("dashboardMessage", "Profil introuvable. Contactez le support AfriReach.", true);
    $("authCard").hidden = false;
    $("memberDashboard").hidden = true;
    return;
  }
  currentProfile = profile;
  $("authCard").hidden = true;
  $("memberDashboard").hidden = false;
  $("welcomeTitle").textContent = "Bonjour, " + profile.display_name;
  $("profileRole").textContent = profile.account_type === "creator" ? "Créateur" : profile.account_type === "advertiser" ? "Annonceur" : "Participant";
  await renderDashboard();
}

async function renderDashboard() {
  const root = $("dashboardContent");
  root.innerHTML = '<div class="dashboard-loading">Chargement de votre espace…</div>';
  const {data:adminRecord} = await db.from("platform_admins").select("user_id").eq("user_id", currentUser.id).maybeSingle();
  if (adminRecord) return renderAdminDashboard(root);
  if (currentProfile.account_type === "advertiser") return renderAdvertiserDashboard(root);
  return renderParticipantDashboard(root);
}

async function renderParticipantDashboard(root) {
  const [{data:campaigns,error:campaignError},{data:applications}] = await Promise.all([
    db.from("campaigns").select("id,title,description,campaign_type,country,participant_reward,participant_slots,status").eq("status","active").order("created_at",{ascending:false}).limit(30),
    db.from("campaign_applications").select("id,campaign_id,status,submission_note,proof_reference,applied_at").eq("participant_id",currentUser.id).order("applied_at",{ascending:false}).limit(30)
  ]);
  const applied = new Set((applications || []).map(a => a.campaign_id));
  const campaignHtml = (campaigns || []).map(c =>
    '<article class="member-item"><div><span class="member-type">' +
    escapeHtml(c.campaign_type.replaceAll("_"," ")) + '</span><h4>' + escapeHtml(c.title) +
    '</h4><p>' + escapeHtml(c.description) + '</p><small>' + escapeHtml(c.country) + ' · ' +
    money(c.participant_reward) + ' · ' + c.participant_slots + ' places</small></div>' +
    '<button class="mini-button" data-apply="' + c.id + '"' +
    (applied.has(c.id) ? ' disabled' : '') + '>' +
    (applied.has(c.id) ? 'Déjà inscrit' : 'Participer') + '</button></article>'
  ).join("");
  const applicationHtml = (applications || []).map(a => {
    const action = a.status === "accepted"
      ? '<label class="upload-proof">Envoyer ma preuve<input type="file" accept="image/jpeg,image/png,image/webp,application/pdf" data-proof="' + a.id + '"></label>'
      : '<span class="status-pill">' + escapeHtml(a.status) + '</span>';
    return '<article class="member-item compact"><div><b>Candidature</b><small>Statut : ' +
      escapeHtml(a.status) + '</small></div>' + action + '</article>';
  }).join("");
  root.innerHTML =
    '<div class="member-summary"><b>Campagnes disponibles</b><span>' + ((campaigns || []).length) + ' campagne(s) active(s)</span></div>' +
    '<div class="member-list">' + (campaignError ? '<p class="empty-state">Impossible de charger les campagnes.</p>' : campaignHtml || '<p class="empty-state">Aucune campagne active pour le moment. Revenez bientôt.</p>') + '</div>' +
    '<h4 class="subheading">Mes candidatures</h4><div class="member-list">' + (applicationHtml || '<p class="empty-state">Vous n\'avez pas encore candidaté.</p>') + '</div>' +
    '<h4 class="subheading">Mes paiements</h4><div id="myPayouts" class="member-list"><p class="empty-state">Chargement…</p></div>';
  root.querySelectorAll("[data-apply]").forEach(button => button.addEventListener("click", () => applyToCampaign(button.dataset.apply, button)));
  root.querySelectorAll("[data-proof]").forEach(input => input.addEventListener("change", () => uploadApplicationProof(input.dataset.proof, input.files?.[0])));
  await loadParticipantPayouts();
}

async function applyToCampaign(campaignId, button) {
  button.disabled = true;
  const {error} = await db.from("campaign_applications").insert({campaign_id:campaignId,participant_id:currentUser.id,status:"applied"});
  if (error && !error.message.includes("duplicate")) showMessage("dashboardMessage", error.message, true);
  else showMessage("dashboardMessage", "Votre candidature a été enregistrée.");
  await renderDashboard();
}

async function uploadApplicationProof(applicationId, file) {
  if (!file) return;
  if (file.size > 5 * 1024 * 1024) return showMessage("dashboardMessage", "Fichier trop volumineux : maximum 5 Mo.", true);
  const allowed = ["image/jpeg","image/png","image/webp","application/pdf"];
  if (!allowed.includes(file.type)) return showMessage("dashboardMessage", "Format refusé. Utilisez JPG, PNG, WEBP ou PDF.", true);
  showMessage("dashboardMessage", "Téléversement de la preuve…");
  const safeName = file.name.replace(/[^a-zA-Z0-9._-]/g,"_");
  const path = `${currentUser.id}/${applicationId}/${Date.now()}-${safeName}`;
  const {error:uploadError} = await db.storage.from("afriareach-proofs").upload(path,file,{upsert:false,contentType:file.type});
  if (uploadError) return showMessage("dashboardMessage", uploadError.message, true);
  const {error:updateError} = await db.from("campaign_applications").update({
    status:"submitted",submission_note:"Preuve envoyée.",proof_reference:path,submitted_at:new Date().toISOString()
  }).eq("id",applicationId);
  if (updateError) return showMessage("dashboardMessage", updateError.message, true);
  showMessage("dashboardMessage", "Preuve transmise. Elle sera examinée par l'annonceur.");
  await renderDashboard();
}

async function loadParticipantPayouts() {
  const target = $("myPayouts");
  if (!target) return;
  const {data,error} = await db.from("participant_payouts").select("id,amount,currency,status,marked_paid_at").eq("participant_id",currentUser.id).order("created_at",{ascending:false});
  target.innerHTML = error ? '<p class="empty-state">Historique indisponible.</p>' : (data || []).map(p => `
    <article class="member-item compact"><div><b>${money(p.amount)}</b><small>${escapeHtml(p.status)}</small></div>${p.status === "marked_paid" ? `<div class="inline-actions"><button class="mini-button" data-confirm-payout="${p.id}">Confirmer reçu</button><button class="mini-button secondary" data-dispute-payout="${p.id}">Signaler</button></div>` : '<span class="status-pill">' + escapeHtml(p.status) + '</span>'}</article>`).join("") || '<p class="empty-state">Aucun paiement enregistré.</p>';
  target.querySelectorAll("[data-confirm-payout]").forEach(b => b.addEventListener("click", () => updatePayout(b.dataset.confirmPayout,{status:"confirmed_by_participant",participant_confirmed_at:new Date().toISOString()})));
  target.querySelectorAll("[data-dispute-payout]").forEach(b => b.addEventListener("click", () => updatePayout(b.dataset.disputePayout,{status:"disputed",dispute_note:"Le participant signale ne pas avoir reçu le paiement."})));
}

async function updatePayout(id, changes) {
  const {error} = await db.from("participant_payouts").update(changes).eq("id",id);
  if (error) showMessage("dashboardMessage",error.message,true);
  else showMessage("dashboardMessage","Votre réponse a été enregistrée.");
  await renderDashboard();
}

async function renderAdvertiserDashboard(root) {
  const [{data:campaigns,error},{data:payouts}] = await Promise.all([
    db.from("campaigns").select("*").eq("advertiser_id",currentUser.id).order("created_at",{ascending:false}),
    db.from("participant_payouts").select("id,amount,status,created_at").eq("advertiser_id",currentUser.id).order("created_at",{ascending:false}).limit(30)
  ]);
  const campaignHtml = (campaigns || []).map(c =>
    '<article class="member-item"><div><span class="status-pill">' + escapeHtml(c.status) +
    '</span><h4>' + escapeHtml(c.title) + '</h4><small>Budget participants : ' +
    money(c.participant_budget) + ' · Frais AfriReach : ' + money(c.service_fee) +
    '</small></div><button class="mini-button" data-view-apps="' + c.id + '">Candidatures</button></article>'
  ).join("");
  const payoutHtml = (payouts || []).map(p =>
    '<article class="member-item compact"><div><b>' + money(p.amount) + '</b><small>' +
    escapeHtml(p.status) + '</small></div>' +
    (p.status === "awaiting_advertiser_payment"
      ? '<button class="mini-button" data-mark-paid="' + p.id + '">J’ai effectué le transfert</button>'
      : '<span class="status-pill">' + escapeHtml(p.status) + '</span>') + '</article>'
  ).join("");
  root.innerHTML =
    '<div class="member-summary"><b>Mes campagnes</b><span>' + ((campaigns || []).length) + ' campagne(s)</span></div>' +
    '<form id="campaignForm" class="campaign-form">' +
    '<h4>Créer une campagne (brouillon)</h4>' +
    '<label>Titre<input name="title" required minlength="5" maxlength="120" placeholder="Ex. Découverte d\'un nouveau service"></label>' +
    '<label>Description<textarea name="description" required minlength="20" maxlength="3000" placeholder="Décrivez la mission, les critères et les preuves attendues"></textarea></label>' +
    '<div class="form-row"><label>Type<select name="campaign_type"><option value="ad_discovery">Découverte publicitaire</option><option value="survey">Sondage</option><option value="product_test">Test produit</option><option value="creator_collaboration">Collaboration créateur</option></select></label>' +
    '<label>Pays<input name="country" value="' + escapeHtml(currentProfile.country || "Togo") + '" required></label></div>' +
    '<label>Objectif<input name="objective" required maxlength="500" placeholder="Résultat recherché"></label>' +
    '<div class="form-row"><label>Récompense / participant (XOF)<input name="participant_reward" type="number" min="1" step="1" required></label><label>Nombre de places<input name="participant_slots" type="number" min="1" max="100000" step="1" required></label></div>' +
    '<label class="check-line"><input name="rules_acknowledged" type="checkbox" required> Je confirme que cette campagne ne manipule pas artificiellement les statistiques des réseaux sociaux.</label>' +
    '<button class="mini-button" type="submit">Enregistrer le brouillon</button>' +
    '<small>Frais de service : 10 % du budget participants, minimum 100 XOF. Calculés automatiquement par la base. Aucune campagne ne sera publiée avant vérification.</small></form>' +
    '<div class="member-list">' + (error ? '<p class="empty-state">Impossible de charger vos campagnes.</p>' : campaignHtml || '<p class="empty-state">Vous n\'avez pas encore créé de campagne.</p>') + '</div>' +
    '<div id="campaignApplications"></div><h4 class="subheading">Paiements directs aux participants</h4>' +
    '<div class="member-list">' + (payoutHtml || '<p class="empty-state">Aucun paiement à effectuer.</p>') + '</div>';
  $("campaignForm")?.addEventListener("submit", createCampaign);
  root.querySelectorAll("[data-mark-paid]").forEach(b => b.addEventListener("click", () => markPayoutPaid(b.dataset.markPaid)));
  root.querySelectorAll("[data-view-apps]").forEach(b => b.addEventListener("click", () => loadCampaignApplications(b.dataset.viewApps)));
}

async function createCampaign(event) {
  event.preventDefault();
  const form = new FormData(event.currentTarget);
  const payload = {
    advertiser_id:currentUser.id,
    title:String(form.get("title")).trim(),
    description:String(form.get("description")).trim(),
    campaign_type:form.get("campaign_type"),
    objective:String(form.get("objective")).trim(),
    country:String(form.get("country")).trim(),
    participant_reward:Number(form.get("participant_reward")),
    participant_slots:Number(form.get("participant_slots")),
    rules_acknowledged:form.get("rules_acknowledged") === "on",
    status:"draft"
  };
  const {error} = await db.from("campaigns").insert(payload);
  if (error) showMessage("dashboardMessage",error.message,true);
  else showMessage("dashboardMessage","Brouillon créé. Les frais sont calculés automatiquement. La campagne reste invisible jusqu'à sa validation.");
  await renderDashboard();
}

async function loadCampaignApplications(campaignId) {
  const panel = $("campaignApplications");
  panel.innerHTML = '<p class="empty-state">Chargement des candidatures…</p>';
  const {data,error} = await db.from("campaign_applications").select("id,participant_id,status,submission_note,proof_reference,applied_at").eq("campaign_id",campaignId).order("applied_at",{ascending:false});
  if (error) return panel.innerHTML = '<p class="empty-state">Erreur : ' + escapeHtml(error.message) + '</p>';
  panel.innerHTML = '<h4 class="subheading">Candidatures reçues</h4>' + ((data || []).map(a => `
    <article class="member-item compact"><div><b>Participant ${escapeHtml(a.participant_id.slice(0,8))}</b><small>Statut : ${escapeHtml(a.status)}</small></div>
    <div class="inline-actions">${a.proof_reference ? '<button class="mini-button secondary" data-proof-open="' + escapeHtml(a.proof_reference) + '">Voir preuve</button>' : ''}
    ${a.status === "applied" ? '<button class="mini-button" data-review="' + a.id + '" data-status="accepted">Accepter</button><button class="mini-button secondary" data-review="' + a.id + '" data-status="rejected">Refuser</button>' : ''}
    ${a.status === "submitted" ? '<button class="mini-button" data-review="' + a.id + '" data-status="approved">Valider la mission</button><button class="mini-button secondary" data-review="' + a.id + '" data-status="rejected">Refuser la preuve</button>' : ''}
    ${a.status === "approved" ? '<button class="mini-button" data-create-payout="' + a.id + '" data-campaign="' + campaignId + '" data-participant="' + a.participant_id + '">Créer paiement direct</button>' : ''}
    </div></article>`).join("") || '<p class="empty-state">Aucune candidature.</p>');
  panel.querySelectorAll("[data-review]").forEach(b => b.addEventListener("click", () => reviewApplication(b.dataset.review,b.dataset.status,campaignId)));
  panel.querySelectorAll("[data-proof-open]").forEach(b => b.addEventListener("click", () => openProof(b.dataset.proofOpen)));
  panel.querySelectorAll("[data-create-payout]").forEach(b => b.addEventListener("click", () => createPayout(b.dataset.createPayout,campaignId,b.dataset.participant)));
}

async function markPayoutPaid(id) {
  const {error} = await db.from("participant_payouts").update({status:"marked_paid",marked_paid_at:new Date().toISOString()}).eq("id",id);
  if (error) showMessage("dashboardMessage",error.message,true);
  else showMessage("dashboardMessage","Paiement marqué comme effectué. Le participant doit confirmer la réception.");
  await renderDashboard();
}

async function reviewApplication(id,status,campaignId) {
  const {error} = await db.from("campaign_applications").update({status,reviewed_at:new Date().toISOString()}).eq("id",id);
  if (error) showMessage("dashboardMessage",error.message,true);
  else showMessage("dashboardMessage","Candidature mise à jour.");
  await loadCampaignApplications(campaignId);
}

async function openProof(path) {
  const {data,error} = await db.storage.from("afriareach-proofs").createSignedUrl(path,120);
  if (error) return showMessage("dashboardMessage",error.message,true);
  window.open(data.signedUrl,"_blank","noopener");
}

async function createPayout(applicationId,campaignId,participantId) {
  const {data:campaign,error:campaignError} = await db.from("campaigns").select("participant_reward").eq("id",campaignId).single();
  if (campaignError) return showMessage("dashboardMessage",campaignError.message,true);
  const {error} = await db.from("participant_payouts").insert({
    application_id:applicationId,campaign_id:campaignId,advertiser_id:currentUser.id,
    participant_id:participantId,amount:campaign.participant_reward,status:"awaiting_advertiser_payment"
  });
  if (error) showMessage("dashboardMessage",error.message,true);
  else showMessage("dashboardMessage","Paiement créé. Effectuez le transfert directement au participant, puis marquez-le comme payé.");
  await loadCampaignApplications(campaignId);
}

async function renderAdminDashboard(root) {
  const [{data:campaigns},{data:fees}] = await Promise.all([
    db.from("campaigns").select("*").order("created_at",{ascending:false}).limit(50),
    db.from("platform_fee_payments").select("*").order("created_at",{ascending:false}).limit(50)
  ]);
  root.innerHTML = `
    <div class="member-summary"><b>Administration AfriReach</b><span>Modération et vérification</span></div>
    <h4 class="subheading">Campagnes à examiner</h4>
    <div class="member-list">${(campaigns || []).map(c => `
      <article class="member-item compact"><div><b>${escapeHtml(c.title)}</b><small>${escapeHtml(c.status)} · Frais : ${money(c.service_fee)}</small></div>
      <div class="inline-actions">${c.status === "pending_review" ? '<button class="mini-button" data-campaign-status="' + c.id + '" data-status="active">Activer</button>' : ''}
      ${["draft","pending_fee_payment","pending_review"].includes(c.status) ? '<button class="mini-button secondary" data-campaign-status="' + c.id + '" data-status="rejected">Rejeter</button>' : ''}</div></article>`).join("") || '<p class="empty-state">Aucune campagne.</p>'}</div>
    <h4 class="subheading">Preuves de frais de service</h4>
    <div class="member-list">${(fees || []).map(f => `
      <article class="member-item compact"><div><b>${money(f.amount)}</b><small>${escapeHtml(f.status)} · Campagne ${escapeHtml(f.campaign_id.slice(0,8))}</small></div>
      <div class="inline-actions">${f.status === "submitted" ? '<button class="mini-button" data-fee="' + f.id + '" data-fee-status="approved">Approuver</button><button class="mini-button secondary" data-fee="' + f.id + '" data-fee-status="rejected">Refuser</button>' : ''}</div></article>`).join("") || '<p class="empty-state">Aucune preuve de paiement reçue.</p>'}</div>`;
  root.querySelectorAll("[data-campaign-status]").forEach(b => b.addEventListener("click", () => updateCampaignStatus(b.dataset.campaignStatus,b.dataset.status)));
  root.querySelectorAll("[data-fee]").forEach(b => b.addEventListener("click", () => reviewFee(b.dataset.fee,b.dataset.feeStatus)));
}

async function updateCampaignStatus(id,status) {
  const {error} = await db.from("campaigns").update({status}).eq("id",id);
  if (error) showMessage("dashboardMessage",error.message,true);
  else showMessage("dashboardMessage","Statut de campagne mis à jour.");
  await renderDashboard();
}

async function reviewFee(id,status) {
  const {error} = await db.from("platform_fee_payments").update({status,reviewed_by:currentUser.id,reviewed_at:new Date().toISOString()}).eq("id",id);
  if (error) return showMessage("dashboardMessage",error.message,true);
  if (status === "approved") {
    const {data:fee} = await db.from("platform_fee_payments").select("campaign_id").eq("id",id).single();
    if (fee) await db.from("campaigns").update({status:"pending_review"}).eq("id",fee.campaign_id);
  }
  showMessage("dashboardMessage","Décision enregistrée.");
  await renderDashboard();
}

$("signOutBtn")?.addEventListener("click", async () => {
  await db.auth.signOut();
  currentUser = null;
  currentProfile = null;
  $("memberDashboard").hidden = true;
  $("authCard").hidden = false;
  setAuthMode("signin");
  showMessage("authMessage","Vous êtes déconnecté.");
});

if (db) {
  db.auth.onAuthStateChange((_event, session) => {
    if (session?.user) setTimeout(() => loadMemberArea(),0);
    else {
      currentUser = null;
      currentProfile = null;
      if ($("memberDashboard")) $("memberDashboard").hidden = true;
      if ($("authCard")) $("authCard").hidden = false;
    }
  });
  loadMemberArea().catch(error => showMessage("authMessage",error.message,true));
} else {
  showMessage("authMessage","Service de connexion indisponible. Vérifiez votre connexion Internet.",true);
}

if ("serviceWorker" in navigator && location.protocol.startsWith("http")) {
  window.addEventListener("load", () => navigator.serviceWorker.register("/sw.js").catch(() => {}));
}
