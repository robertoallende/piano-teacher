```fancy-kanban
---
title: Piano Teacher
fields:
  - name: status, type: Select, options: inbox|doing|done, label: Status, default: inbox
  - name: title, type: Text, label: Title
  - name: description, type: Textarea, label: Description
  - name: assignee, type: Select, options: piano-teacher|roberto, label: Assignee
  - name: session_date, type: Date, label: Session Date
  - name: docs, type: File, label: Docs
workflow: inbox→doing, doing→done, doing→inbox, done→doing
---

| _id | Status | Title | Description | Assignee | Session Date | Docs |
| --- | --- | --- | --- | --- | --- | --- |
```
