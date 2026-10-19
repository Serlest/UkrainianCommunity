(function () {
  document.querySelectorAll(".site-header .brand").forEach((brand) => {
    brand.href = "/uac";
    brand.setAttribute("aria-label", "UAC — Ukrainian Community Austria");
    brand.innerHTML = '<span class="brand-name">UAC<small>Ukrainian Community Austria</small></span>';
  });
  const navigationLabels = {
    "/support": ["Support", "Підтримка"],
    "/privacy": ["Datenschutz", "Конфіденційність"],
    "/terms": ["Bedingungen", "Умови"],
    "/imprint": ["Impressum", "Impressum"],
    "/organization-rules": ["Organisationen", "Організації"],
    "/report-illegal-content": ["Inhalt melden", "Повідомити"]
  };
  document.querySelectorAll(".nav-links a, .footer-links a").forEach((link) => {
    const labels = navigationLabels[new URL(link.href).pathname];
    if (labels) link.innerHTML = `<span data-lang="de">${labels[0]}</span><span data-lang="uk">${labels[1]}</span>`;
  });
  let icon = document.querySelector('link[rel="icon"]');
  if (!icon) {
    icon = document.createElement("link");
    icon.rel = "icon";
    document.head.appendChild(icon);
  }
  icon.href = "/assets/uac-icon.png";
  icon.type = "image/png";
  document.querySelectorAll('.nav-links a').forEach((link) => {
    if (new URL(link.href).pathname === location.pathname.replace(/\/$/, "")) {
      link.setAttribute("aria-current", "page");
    }
  });
  const supported = new Set(["de", "uk"]);
  let stored;
  try { stored = localStorage.getItem("uc-language"); } catch (_) { /* Storage may be unavailable. */ }
  const browserLanguage = (navigator.language || "de").toLowerCase().startsWith("uk") ? "uk" : "de";
  const requested = new URLSearchParams(location.search).get("lang");
  const initial = supported.has(requested) ? requested : (supported.has(stored) ? stored : browserLanguage);
  const translated = [...document.querySelectorAll("[data-copy-de]")].map(element => ({element, uk:element.innerHTML, de:element.dataset.copyDe}));
  const translatedAttributes = ["aria-label", "alt", "content"].flatMap(attribute =>
    [...document.querySelectorAll(`[data-${attribute}-de]`)].map(element => ({element, attribute, uk:element.getAttribute(attribute), de:element.getAttribute(`data-${attribute}-de`)}))
  );

  function applyLanguage(language) {
    const selected = supported.has(language) ? language : "de";
    document.documentElement.lang = selected;
    const url = new URL(location.href);
    if (url.searchParams.has("lang")) {
      url.searchParams.set("lang", selected);
      history.replaceState(null, "", url);
    }
    translated.forEach(({element, uk, de}) => { element.innerHTML = selected === "de" ? de : uk; });
    translatedAttributes.forEach(({element, attribute, uk, de}) => { element.setAttribute(attribute, selected === "de" ? de : uk); });
    document.querySelectorAll("[data-language-button]").forEach((button) => {
      button.setAttribute("aria-pressed", String(button.dataset.languageButton === selected));
    });
    const titles = document.body.dataset;
    document.title = selected === "uk" ? titles.titleUk : titles.titleDe;
    try { localStorage.setItem("uc-language", selected); } catch (_) { /* Keep the language usable without storage. */ }
  }

  document.querySelectorAll("[data-language-button]").forEach((button) => {
    button.addEventListener("click", () => applyLanguage(button.dataset.languageButton));
  });

  document.querySelectorAll("[data-current-year]").forEach((element) => {
    element.textContent = String(new Date().getFullYear());
  });

  applyLanguage(initial);
})();
