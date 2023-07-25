import os
import sqlite3
from typing import Optional

import uvicorn
from fastapi import FastAPI, HTTPException
from pydantic import BaseModel

app = FastAPI()

db_path = "/app/data/database.db"
os.makedirs(os.path.dirname(db_path), exist_ok=True)

conn = sqlite3.connect(db_path)
c = conn.cursor()

c.execute("""
    CREATE TABLE IF NOT EXISTS visits (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        entry INTEGER NOT NULL,
        exit INTEGER NOT NULL,
        keystrokes INTEGER NOT NULL,
        filepath TEXT NOT NULL
    )
""")

c.execute("""
    CREATE TABLE IF NOT EXISTS fileinfo (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        filepath TEXT UNIQUE NOT NULL,
        filetype TEXT,
        projectname TEXT,
        lastmodification INTEGER NOT NULL
    )
""")

conn.commit()


class Visit(BaseModel):
    entry: int
    exit: int
    keystrokes: int
    filepath: str
    filetype: Optional[str]
    projectname: Optional[str]


class FileInfo(BaseModel):
    filepath: str
    filetype: Optional[str]
    projectname: Optional[str]
    lastmodification: int


@app.get("/status")
async def status():
    return {"status": "ok", "alive": True}


@app.post("/visit")
async def create_visit(visit: Visit):
    try:
        c.execute("SELECT * FROM fileinfo WHERE filepath=?", (visit.filepath,))
        existing_file = c.fetchone()

        if existing_file:
            c.execute("UPDATE fileinfo SET lastmodification=? WHERE filepath=?", (visit.exit, visit.filepath))
        else:
            file_info = FileInfo(filepath=visit.filepath,
                                 filetype=visit.filetype,
                                 projectname=visit.projectname,
                                 lastmodification=visit.exit)
            c.execute("INSERT INTO fileinfo (filepath, filetype, projectname, lastmodification) VALUES (?, ?, ?, ?)",
                      (file_info.filepath, file_info.filetype, file_info.projectname, file_info.lastmodification))

        c.execute("INSERT INTO visits (entry, exit, keystrokes, filepath) VALUES (?, ?, ?, ?)",
                  (visit.entry, visit.exit, visit.keystrokes, visit.filepath))

        conn.commit()

        return {"message": "Visit created successfully"}

    except sqlite3.Error as e:
        raise HTTPException(status_code=500, detail=str(e))


@app.delete("/cleanup")
async def delete_visit(threshold_in_min: float = 24 * 60):
    # delete all entries where the elapsed time is more than the threshold
    # elapsed time can be calulated by exit - entry
    threshold_in_sec = threshold_in_min * 60
    try:
        c.execute("SELECT filepath, entry, exit FROM visits WHERE (exit - entry) > ?", (threshold_in_sec,))
        entries_to_delete = c.fetchall()
        entries_to_delete = [{"filepath": entry[0], "entry": entry[1], "exit": entry[2]} for entry in entries_to_delete]

        c.execute("DELETE FROM visits WHERE (exit - entry) > ?", (threshold_in_sec,))
        conn.commit()
        if len(entries_to_delete) > 0:
            return {"message": "Visit deleted successfully", "entries": entries_to_delete}
        else:
            return {"message": "No entries to delete"}
    except sqlite3.Error as e:
        raise HTTPException(status_code=500, detail=str(e))


if __name__ == "__main__":
    uvicorn.run(app, host="0.0.0.0", port=8000)
