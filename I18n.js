.pragma library
// Interface text in other languages, keyed by the English text itself, so a
// string missing from a table shows in English. tr("Copied: %1", x) fills in
// %1, %2… after the lookup. The same scheme as predmaxim.datebook: Quickshell
// plugins get no .qm catalogues, so Qt's qsTr isn't used.
var TABLES = {
  ru: {
    // The list
    "My issues": "Мои задачи", "All issues": "Все задачи",
    "Show subtasks": "Показать подзадачи", "Hide subtasks": "Скрыть подзадачи",
    "Refresh": "Обновить", "Connection": "Подключение", "Back": "Назад",
    "Open the board in the browser": "Открыть доску в браузере",
    "Issue key or number": "Ключ или номер задачи",
    "Found": "Найдено", "Searching…": "Поиск…", "Nothing found": "Ничего не найдено",
    "A key like ABC-12 or a number": "Ключ вида ABC-12 или номер",
    "Loading…": "Загрузка…", "No issues": "Нет задач", "Pick an issue": "Выберите задачу",
    "Project %1 has no board": "У проекта %1 нет доски",
    // Settings
    "Jira address": "Адрес Jira", "Project key": "Ключ проекта",
    "Personal access token · empty keeps the current one": "Personal access token · пусто — не менять",
    "Profile → Personal Access Tokens → Create token": "Профиль → Personal Access Tokens → Create token",
    "Save": "Сохранить", "Cancel": "Отмена",
    "An address like https://jira.example.com": "Адрес вида https://jira.example.ru",
    "A project key is needed": "Нужен ключ проекта",
    "Token not saved: %1": "Токен не сохранён: %1", "keyring error": "ошибка keyring",
    // The card
    "Open": "Открыть", "Flagged": "С флагом", "Add flag": "Поставить флаг", "Remove flag": "Снять флаг", "Comments": "Комментарии", "New comment": "Новый комментарий", "Comment": "Комментировать", "Flag and comment": "Флаг и комментарий", "No comments": "Нет комментариев",
    "Edit the title": "Изменить название",
    "No description": "Описания нет",
    "Attachments": "Вложения", "downloading…": "скачивается…", "Subtasks": "Подзадачи",
    "Status": "Статус", "Priority": "Приоритет", "Type": "Тип", "Story points": "Story points",
    "Epic": "Эпик", "Labels": "Метки", "space-separated": "через пробел",
    "Reporter": "Постановщик", "Assignee": "Исполнитель", "Unassigned": "Не назначен",
    "Assign to me": "Назначить себя", "Story points must be a number": "Story points — число",
    "Copied: %1": "Скопировано: %1", "key": "номер", "title": "название", "link": "ссылка",
    // Downloads
    "Downloaded: %1": "Скачано: %1", "Not downloaded: %1": "Не скачано: %1", "download failed": "ошибка загрузки",
    // Errors (Model.errorText, scripts/jira)
    "429: rate limit, or the token wasn't accepted — refresh in a minute":
      "429: лимит запросов или токен не принят — обновите через минуту",
    "unknown error": "неизвестная ошибка",
    "no token — set it in the settings (gear)": "нет токена — задайте его в настройках (шестерёнка)",
    "the attachment isn't on this Jira": "вложение не с этой Jira",
    "empty token": "пустой токен",
    // Sizes (Model.sizeText)
    "B": "Б", "KB": "КБ", "MB": "МБ", "GB": "ГБ"
  }
}

// Text follows LC_MESSAGES, overridden by LC_ALL and defaulting to LANG, as
// the system splits it. env is name -> value (Quickshell.env in QML).
function textLanguage(env) {
  var names = ["LC_ALL", "LC_MESSAGES", "LANG"]
  for (var i = 0; i < names.length; i++) {
    var v = String(env(names[i]) || "").split(".")[0].split("@")[0]
    if (v && v !== "C" && v !== "POSIX") {
      var l = v.slice(0, 2).toLowerCase()
      return TABLES[l] ? l : "en"
    }
  }
  return "en"
}

function translator(lang) {
  var table = TABLES[lang] || {}
  return function(text) {
    var out = Object.prototype.hasOwnProperty.call(table, text) ? table[text] : text
    for (var i = 1; i < arguments.length; i++) out = out.split("%" + i).join(String(arguments[i]))
    return out
  }
}
