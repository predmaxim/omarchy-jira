# Jira

My Jira Server issues in one project: a list and an editable issue card.

![Jira](preview.png)

## Without the bar icon

The modal and the IPC target (`omarchy-shell predmaxim.jira toggle`) live in
the bar widget, so the widget stays in the bar; to hide its icon and open Jira
from a hotkey only:

```
omarchy bar set predmaxim.jira showIcon false --json
```

`true` brings the icon back.
