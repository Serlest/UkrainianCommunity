(function () {
  const supported = new Set(["de", "uk"]);
  const stored = localStorage.getItem("uc-language");
  const browserLanguage = (navigator.language || "de").toLowerCase().startsWith("uk") ? "uk" : "de";
  const initial = supported.has(stored) ? stored : browserLanguage;

  function applyLanguage(language) {
    const selected = supported.has(language) ? language : "de";
    document.documentElement.lang = selected;
    document.querySelectorAll("[data-language-button]").forEach((button) => {
      button.setAttribute("aria-pressed", String(button.dataset.languageButton === selected));
    });
    const titles = document.body.dataset;
    document.title = selected === "uk" ? titles.titleUk : titles.titleDe;
    localStorage.setItem("uc-language", selected);
  }

  document.querySelectorAll("[data-language-button]").forEach((button) => {
    button.addEventListener("click", () => applyLanguage(button.dataset.languageButton));
  });

  document.querySelectorAll("[data-current-year]").forEach((element) => {
    element.textContent = String(new Date().getFullYear());
  });

  applyLanguage(initial);
})();
