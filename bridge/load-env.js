import { config } from "dotenv";
import { dirname } from "path";
import { fileURLToPath } from "url";

config({ path: `${dirname(fileURLToPath(import.meta.url))}/.env` });
