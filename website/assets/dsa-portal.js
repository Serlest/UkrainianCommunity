(function () {
  const endpoint = "/api/dsa";
  const noticeForm = document.querySelector("#dsa-notice-form");
  const statusForm = document.querySelector("#dsa-status-form");
  if (!noticeForm || !statusForm) return;

  const language = () => document.documentElement.lang === "uk" ? "uk" : "de";
  const words = (de, uk) => language() === "uk" ? uk : de;
  const message = (element, text, kind) => {
    element.hidden = false;
    element.className = `dsa-message ${kind || ""}`;
    element.textContent = text;
  };
  const post = async (body) => {
    const response = await fetch(endpoint, {
      method: "POST",
      headers: {"Content-Type": "application/json"},
      body: JSON.stringify(body),
    });
    const payload = await response.json();
    if (!response.ok) throw new Error(payload.error || "Request failed");
    return payload;
  };

  document.querySelectorAll("[data-dsa-tab]").forEach((button) => {
    button.addEventListener("click", () => {
      const showNotice = button.dataset.dsaTab === "notice";
      noticeForm.hidden = !showNotice;
      statusForm.hidden = showNotice;
      document.querySelectorAll("[data-dsa-tab]").forEach((tab) => tab.classList.toggle("is-active", tab === button));
    });
  });

  const contactException = noticeForm.elements.contactException;
  const category = noticeForm.elements.category;
  const syncContactRequirement = () => {
    const allowed = category.value === "childSafety";
    contactException.disabled = !allowed;
    if (!allowed) contactException.checked = false;
    [noticeForm.elements.reporterName, noticeForm.elements.reporterEmail].forEach((field) => {
      field.required = !contactException.checked;
      field.disabled = contactException.checked;
    });
  };
  category.addEventListener("change", syncContactRequirement);
  contactException.addEventListener("change", syncContactRequirement);
  syncContactRequirement();

  noticeForm.addEventListener("submit", async (event) => {
    event.preventDefault();
    if (!noticeForm.reportValidity()) return;
    const output = noticeForm.querySelector("[data-dsa-notice-message]");
    const button = noticeForm.querySelector("button[type=submit]");
    button.disabled = true;
    message(output, words("Meldung wird sicher übermittelt …", "Скаргу безпечно надсилаємо…"));
    try {
      const data = Object.fromEntries(new FormData(noticeForm).entries());
      data.action = "submit";
      data.goodFaithConfirmed = noticeForm.elements.goodFaithConfirmed.checked;
      data.contactException = contactException.checked;
      data.preferredLanguage = language();
      const receipt = await post(data);
      localStorage.setItem("uc-dsa-case", JSON.stringify({caseNumber: receipt.caseNumber, accessToken: receipt.accessToken}));
      message(output, words(
        `Eingang bestätigt. Vorgang: ${receipt.caseNumber}. Zugangscode: ${receipt.accessToken}. Speichern Sie beides jetzt sicher; der Code wird nicht erneut angezeigt.`,
        `Отримання підтверджено. Справа: ${receipt.caseNumber}. Код доступу: ${receipt.accessToken}. Збережіть обидва значення зараз; код повторно не показується.`,
      ), "success");
      statusForm.elements.caseNumber.value = receipt.caseNumber;
      statusForm.elements.accessToken.value = receipt.accessToken;
      noticeForm.reset();
      syncContactRequirement();
    } catch (error) {
      message(output, words("Die Meldung konnte nicht übermittelt werden. Prüfen Sie die Angaben und versuchen Sie es erneut.", "Не вдалося надіслати скаргу. Перевірте дані та повторіть спробу."), "error");
    } finally {
      button.disabled = false;
    }
  });

  function renderCase(result) {
    const container = statusForm.querySelector("[data-dsa-case-result]");
    const decision = result.decision;
    const appeal = result.appeal;
    container.hidden = false;
    container.innerHTML = "";
    const card = document.createElement("div");
    card.className = "case-card";
    const heading = document.createElement("h3");
    heading.textContent = `${result.caseNumber} · ${result.status}`;
    card.appendChild(heading);
    if (decision) {
      const details = document.createElement("dl");
      const rows = [
        [words("Entscheidung", "Рішення"), decision.outcome],
        [words("Tatsachen und Gründe", "Факти та причини"), decision.factsAndCircumstances],
        [words("Rechtsgrundlage", "Правова підстава"), decision.legalBasis || "—"],
        [words("Regelgrundlage", "Підстава за правилами"), decision.termsBasis || "—"],
        [words("Gebiet / Dauer", "Територія / строк"), `${decision.territorialScope} · ${decision.duration}`],
        [words("Automatisierung", "Автоматизація"), decision.automationUsed ? words("Ja", "Так") : words("Nein, menschliche Entscheidung", "Ні, рішення людини")],
        [words("Rechtsbehelf", "Оскарження"), decision.redressInformation],
      ];
      rows.forEach(([term, value]) => {
        const dt = document.createElement("dt"); dt.textContent = term;
        const dd = document.createElement("dd"); dd.textContent = value;
        details.append(dt, dd);
      });
      card.appendChild(details);
      if (!appeal && decision.appealDeadline && new Date(decision.appealDeadline) > new Date()) {
        const appealForm = document.createElement("form");
        appealForm.className = "appeal-form";
        appealForm.innerHTML = `<label>${words("Begründung des Einspruchs", "Обґрунтування оскарження")}<textarea name="reason" maxlength="5000" required></textarea></label><button class="button button-secondary" type="submit">${words("Kostenlosen Einspruch senden", "Подати безкоштовне оскарження")}</button>`;
        appealForm.addEventListener("submit", async (event) => {
          event.preventDefault();
          if (!appealForm.reportValidity()) return;
          try {
            await post({action: "appeal", caseNumber: statusForm.elements.caseNumber.value, accessToken: statusForm.elements.accessToken.value, reason: appealForm.elements.reason.value});
            await loadStatus();
          } catch (error) {
            message(statusForm.querySelector("[data-dsa-status-message]"), words("Einspruch konnte nicht gesendet werden.", "Не вдалося подати оскарження."), "error");
          }
        });
        card.appendChild(appealForm);
      }
    }
    if (appeal) {
      const appealText = document.createElement("p");
      appealText.textContent = `${words("Einspruch", "Оскарження")}: ${appeal.status}${appeal.reason ? ` · ${appeal.reason}` : ""}`;
      card.appendChild(appealText);
    }
    container.appendChild(card);
  }

  async function loadStatus() {
    const output = statusForm.querySelector("[data-dsa-status-message]");
    const result = await post({action: "status", caseNumber: statusForm.elements.caseNumber.value, accessToken: statusForm.elements.accessToken.value});
    output.hidden = true;
    renderCase(result);
  }
  statusForm.addEventListener("submit", async (event) => {
    event.preventDefault();
    if (!statusForm.reportValidity()) return;
    try { await loadStatus(); } catch (error) {
      message(statusForm.querySelector("[data-dsa-status-message]"), words("Fall oder Zugangscode wurde nicht gefunden.", "Справу або код доступу не знайдено."), "error");
    }
  });

  try {
    const saved = JSON.parse(localStorage.getItem("uc-dsa-case") || "null");
    if (saved) {
      statusForm.elements.caseNumber.value = saved.caseNumber || "";
      statusForm.elements.accessToken.value = saved.accessToken || "";
    }
  } catch (_) { /* Ignore invalid local data. */ }
})();
