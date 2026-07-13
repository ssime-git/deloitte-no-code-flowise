import { __export } from "../_virtual/rolldown_runtime.js";
import { getEnvironmentVariable } from "@langchain/core/utils/env";
import { Embeddings } from "@langchain/core/embeddings";
import { chunkArray } from "@langchain/core/utils/chunk_array";

//#region src/embeddings/jina.ts
var jina_exports = {};
__export(jina_exports, { JinaEmbeddings: () => JinaEmbeddings });
var JinaEmbeddings = class extends Embeddings {
	model = "jina-clip-v2";
	batchSize = 24;
	baseUrl = "https://api.jina.ai/v1/embeddings";
	stripNewLines = true;
	dimensions = 1024;
	apiKey;
	normalized = true;
	constructor(fields) {
		const fieldsWithDefaults = {
			maxConcurrency: 2,
			...fields
		};
		super(fieldsWithDefaults);
		const apiKey = fieldsWithDefaults?.apiKey || getEnvironmentVariable("JINA_API_KEY") || getEnvironmentVariable("JINA_AUTH_TOKEN");
		if (!apiKey) throw new Error("Jina API key not found");
		this.apiKey = apiKey;
		this.model = fieldsWithDefaults?.model ?? this.model;
		this.dimensions = fieldsWithDefaults?.dimensions ?? this.dimensions;
		this.batchSize = fieldsWithDefaults?.batchSize ?? this.batchSize;
		this.stripNewLines = fieldsWithDefaults?.stripNewLines ?? this.stripNewLines;
		this.normalized = fieldsWithDefaults?.normalized ?? this.normalized;
	}
	doStripNewLines(input) {
		if (this.stripNewLines) return input.map((i) => {
			if (typeof i === "string") return i.replace(/\n/g, " ");
			if (i.text) return { text: i.text.replace(/\n/g, " ") };
			return i;
		});
		return input;
	}
	async embedDocuments(input) {
		// ponytail: sequential batches — upstream fires ALL batches via Promise.all,
		// which blows Jina's 2-concurrent-requests limit on large upserts.
		const batches = chunkArray(this.doStripNewLines(input), this.batchSize);
		const embeddings = [];
		for (let i = 0; i < batches.length; i += 1) {
			const batchResponse = (await this.embeddingWithRetry(this.getParams(batches[i]))) || [];
			for (let j = 0; j < batches[i].length; j += 1) embeddings.push(batchResponse[j]);
		}
		return embeddings;
	}
	async embedQuery(input) {
		const params = this.getParams(this.doStripNewLines([input]), true);
		const embeddings = await this.embeddingWithRetry(params) || [[]];
		return embeddings[0];
	}
	getParams(input, query) {
		return {
			model: this.model,
			input,
			dimensions: this.dimensions,
			task: query ? "retrieval.query" : "retrieval.passage",
			normalized: this.normalized
		};
	}
	async embeddingWithRetry(body) {
		// ponytail: upstream "WithRetry" never retried; retry rate/concurrency errors with backoff
		for (let attempt = 0; ; attempt += 1) {
			const response = await fetch(this.baseUrl, {
				method: "POST",
				headers: {
					"Content-Type": "application/json",
					Authorization: `Bearer ${this.apiKey}`
				},
				body: JSON.stringify(body)
			});
			const embeddingData = await response.json();
			if ("detail" in embeddingData && embeddingData.detail) {
				const detail = `${embeddingData.detail}`;
				const retryable = response.status === 429 || response.status === 503 || /limit/i.test(detail);
				if (retryable && attempt < 5) {
					await new Promise((r) => setTimeout(r, 2000 * (attempt + 1)));
					continue;
				}
				throw new Error(detail);
			}
			return embeddingData.data.map(({ embedding }) => embedding);
		}
	}
};

//#endregion
export { JinaEmbeddings, jina_exports };
//# sourceMappingURL=jina.js.map