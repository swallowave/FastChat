{
  inputs = {
    # torch 2.0:
    # - optional cuda support: https://github.com/NixOS/nixpkgs/pull/224898
    #
    # rocfft: doesn't cache in hydra (Output limit exceeded)
    # - https://hydra.nixos.org/job/nixpkgs/trunk/rocfft.x86_64-linux
    nixpkgs.url = "github:NixOS/nixpkgs/74c56f2e51d08f0196ed48d32e01d5d408e64451";
  };

  outputs = { self, nixpkgs }@inputs:
    let
      lib = nixpkgs.lib;

      pkgs = import nixpkgs {
        overlays = with self.overlays; [
          default
        ];

        system = "x86_64-linux";
      };

      llama = (builtins.mapAttrs makeLlama
        {
          "7b" = "sha256-4rmndGpPjSUNKxQymRrpBkIYodebw1Ohuyx/EB0S9V8=";
          "13b" = "sha256-c1CB/AFXJ0jW3c0V35Kf2xLqB/7svrkeNaG7wQjijBg=";
        })
      // {
        tokenizer = pkgs.requireFile {
          name = "tokenizer.model";
          message = "Missing LLaMA tokenizer model: nix store add-file tokenizer.model";
          sha256 = "sha256-nlVq/UQhO2vRviuFDru9mPVIFDeoAhr69Y7n+xgY00c=";
        };
      };

      makeLlama = variant: hash:
        let
          name = lib.toUpper variant;

          model = pkgs.requireFile {
            inherit name;
            message = "Missing LLaMA ${name} model: nix store add-path ${name}";
            hashMode = "recursive";
            sha256 = hash;
          };

          hf = pkgs.runCommand "llama-${variant}-hf"
            {
              nativeBuildInputs = [
                (pkgs.python3.withPackages (py: with py; [
                  accelerate
                  transformers
                  sentencepiece
                ]))
              ];
            }
            ''
              python -m transformers.models.llama.convert_llama_weights_to_hf \
                --input_dir ${pkgs.linkFarm "llama" [
                  { name = "tokenizer.model"; path = llama.tokenizer; }
                  { inherit name; path = model; }
                ]} \
                --model_size ${name} \
                --output_dir "$out"

              rm "$out/tokenizer.model"
              ln -s ${llama.tokenizer} "$out/tokenizer.model"
            '';
        in model // { inherit hf; };

      vicuna = builtins.mapAttrs
        (version: meta: (builtins.mapAttrs (makeVicuna version) meta))
        {
          "0" = {
            "7b" = {
              rev = "829f942ab9220c23ea6ce1d32c8eea53572ddaca";
              hash = "sha256-fnbdcstbVo7M3U1W6L2uAuAJpBvgi5a2A4PxCcq/VJI=";
            };
            "13b" = {
              rev = "b250abe4caef98e5fd575dec6ae63291149b0107";
              hash = "sha256-ER1AxMR0KDv+NnKcJsLMCMInF3+4HcbP9GurP9at3QU=";
            };
          };

          "1.1" = {
            "7b" = {
              rev = "e0f77843570301ca189e2c424e1840167cf64d5a";
              hash = "sha256-SAmmsDSqtBHcnevDUipIX3l82uj2v687NpdlEgWoALQ=";
            };
            "13b" = {
              rev = "561422e977c19d877fbcd12e1e30b1cda820c642";
              hash = "sha256-j4bzpATCwJNHM+DK9QBd7QGDl+mcQ5rTymooXGWjN6g=";
            };
          };
        };

      makeVicuna = version: variant: { rev, hash }:
        let
          delta = pkgs.fetchgit {
            url = "https://huggingface.co/lmsys/vicuna-${variant}-delta-v${version}";
            fetchLFS = true;
            inherit rev;
            inherit hash;
          };

          model = pkgs.runCommand "vicuna-${version}-${variant}"
            {
              nativeBuildInputs = [
                (pkgs.python3.withPackages (py: with py; [
                  accelerate
                  transformers
                  sentencepiece
                ]))
              ];
            }
            ''
              python ${./fastchat/model/apply_delta.py} \
                --base-model-path ${llama.${variant}.hf} \
                --target-model-path "$out" \
                --delta-path ${delta}

              rm "$out/tokenizer.model"
              ln -s ${llama.tokenizer} "$out/tokenizer.model"
            '';
        in model // { inherit delta; };
    in
      {
        packages."x86_64-linux" = {
          "model/llama/7b" = llama."7b";
          "model/llama/7b/hf" = llama."7b".hf;
          "model/llama/13b" = llama."13b";
          "model/llama/13b/hf" = llama."13b".hf;
          "model/llama/tokenizer" = llama.tokenizer;
          "model/vicuna/v0/7b" = vicuna."0"."7b";
          "model/vicuna/v0/7b/delta" = vicuna."0"."7b".delta;
          "model/vicuna/v0/13b" = vicuna."0"."13b";
          "model/vicuna/v0/13b/delta" = vicuna."0"."13b".delta;
          "model/vicuna/v1-1/7b" = vicuna."1.1"."7b";
          "model/vicuna/v1-1/7b/delta" = vicuna."1.1"."7b".delta;
          "model/vicuna/v1-1/13b" = vicuna."1.1"."13b";
          "model/vicuna/v1-1/13b/delta" = vicuna."1.1"."13b".delta;
        };

        overlays = {
          default = finalPkgs: prevPkgs: {
            pythonPackagesExtensions = prevPkgs.pythonPackagesExtensions ++ [
              (finalPy: prevPy: {
                # Replaces: https://github.com/NixOS/nixpkgs/pull/214694
                accelerate = finalPy.callPackage (
                  { lib
                  , buildPythonPackage
                  , fetchFromGitHub
                  , numpy
                  , packaging
                  , psutil
                  , pyyaml
                  , torch
                  , evaluate
                  , parameterized
                  , pytest-subtests
                  , pytestCheckHook
                  , transformers
                  }:

                  buildPythonPackage rec {
                    pname = "accelerate";
                    version = "0.18.0";
                    format = "pyproject";

                    src = fetchFromGitHub {
                      owner = "huggingface";
                      repo = "accelerate";
                      rev = "refs/tags/v${version}";
                      hash = "sha256-fCIvVbMaWAWzRfPc5/1CZq3gZ8kruuk9wBt8mzLHmyw=";
                    };

                    propagatedBuildInputs = [
                      numpy
                      packaging
                      psutil
                      pyyaml
                      torch
                    ];

                    nativeCheckInputs = [
                      evaluate
                      parameterized
                      pytest-subtests
                      pytestCheckHook
                      transformers
                    ];

                    preCheck = ''
                      export HOME=$TMPDIR
                      export PATH="$out/bin:$PATH"
                    '';

                    pythonImportsCheck = [
                      "accelerate"
                    ];

                    disabledTests = [
                      # Requires access to HuggingFace to download checkpoints
                      "test_infer_auto_device_map_on_t0pp"
                    ];

                    disabledTestPaths = [
                      # Files under this path are used as scripts in tests,
                      # and shouldn't be treated as pytest sources
                      "src/accelerate/test_utils/scripts"

                      # Requires access to HuggingFace to download checkpoints
                      "tests/test_examples.py"
                    ];

                    meta = with lib; {
                      description = "A simple way to train and use PyTorch models with multi-GPU, TPU, mixed-precision";
                      homepage = "https://github.com/huggingface/accelerate";
                      license = licenses.asl20;
                      maintainers = with maintainers; [ kira-bruneau ];
                    };
                  }
                ) { };

                tokenizers = prevPy.tokenizers.overrideAttrs (finalAttrs: prevAttrs: {
                  version = "0.13.3";

                  src = finalPkgs.fetchFromGitHub {
                    owner = "huggingface";
                    repo = "tokenizers";
                    rev = "refs/tags/python-v${finalAttrs.version}";
                    hash = "sha256-QZG5jmr3vbyQs4mVBjwVDR31O66dUM+p39R0htJ1umk=";
                  };

                  cargoDeps = finalPkgs.rustPlatform.importCargoLock {
                    lockFile = ./Cargo.lock;
                  };

                  postPatch = ''
                    ln -s ${./Cargo.lock} Cargo.lock
                  '';
                });

                transformers = prevPy.transformers.overrideAttrs (finalAttrs: prevAttrs: {
                  version = "4.28.1";

                  src = finalPkgs.fetchFromGitHub {
                    owner = "huggingface";
                    repo = "transformers";
                    rev = "refs/tags/v${finalAttrs.version}";
                    hash = "sha256-FmiuWfoFZjZf1/GbE6PmSkeshWWh+6nDj2u2PMSeDk0=";
                  };
                });
              })
            ];
          };
        };

        devShells."x86_64-linux".default = pkgs.mkShell {
          packages = [
            (pkgs.python3.withPackages (py: with py; [
              accelerate
              fastapi
              # gradio (not packaged: demo server)
              httpx
              markdown2
              numpy
              prompt-toolkit
              pydantic
              requests
              rich
              sentencepiece
              shortuuid
              # tokenizers (not used)
              (lib.hiPrio torchWithRocm)
              transformers
              uvicorn
              # wandb (dev tool only)
            ]))
          ];
        };
      };
}
