package <seu.pacote>.web;   // ajuste o pacote; o resto copia sem mudança

import static org.assertj.core.api.Assertions.assertThat;

import java.io.IOException;
import java.io.InputStream;
import java.nio.charset.StandardCharsets;
import java.util.ArrayDeque;
import java.util.ArrayList;
import java.util.Deque;
import java.util.List;
import java.util.regex.Matcher;
import java.util.regex.Pattern;

import org.junit.jupiter.api.Test;

/**
 * O DaisyUI esmaece vários textos por padrão (cabeçalho de tabela, aba inativa, rótulo...) com
 * {@code color-mix} de {@code base-content}, e abaixo de 70% isso fica sob os 4,5:1 nos dois fundos
 * do tema {@code basis-interno}. O {@code input.css} sobrescreve cada um; este teste garante que
 * nenhum ficou de fora, inclusive os que uma atualização do DaisyUI venha a trazer.
 *
 * <p>Lê o CSS que o build gera (sem minificar, uma declaração por linha) e, para cada {@code color}
 * esmaecido abaixo de 70% num estado ativo, exige uma regra posterior com o mesmo seletor, sob as
 * mesmas condições de {@code @media}/{@code @container}, e 70% ou mais. Estados desabilitados e
 * placeholders ficam de fora: a exigência de contraste da WCAG não vale para componente inativo.
 */
class ContrasteDoTemaTest {

    private static final int MINIMO = 70;

    private static final Pattern COR_ESMAECIDA = Pattern.compile(
            "^color:\\s*color-mix\\(in oklab,\\s*(?:var\\(--color-base-content\\)|currentColor)\\s+(\\d+)%");

    /** {@code :not(...)} sem parênteses aninhados; repetido até sumir, para cobrir os aninhados. */
    private static final Pattern NEGACAO = Pattern.compile(":not\\([^()]*\\)");

    private record Cor(String regra, String seletor, int percentual, int linha) {
    }

    @Test
    void nenhumTextoAtivoFicaEsmaecidoAbaixoDe70PorCento() throws IOException {
        String css = cssGerado();

        assertThat(cores(css)).as("o CSS gerado deveria ter as regras do DaisyUI").isNotEmpty();
        assertThat(semSobrescrita(css)).isEmpty();
    }

    @Test
    void regraNovaEsmaecidaSemSobrescritaReprova() {
        assertThat(semSobrescrita("""
                .novo {
                  color: color-mix(in oklab, var(--color-base-content) 60%, transparent);
                }
                """)).containsExactly("60% em .novo (linha 2)");
    }

    @Test
    void negacaoDeDesabilitadoContinuaSendoEstadoAtivo() {
        assertThat(semSobrescrita("""
                .novo {
                  &:not(:disabled) {
                    color: color-mix(in oklab, var(--color-base-content) 60%, transparent);
                  }
                }
                """)).hasSize(1);
    }

    @Test
    void sobrescritaSoNumaLarguraNaoValeParaAsOutras() {
        assertThat(semSobrescrita("""
                .novo {
                  color: color-mix(in oklab, var(--color-base-content) 60%, transparent);
                }
                @media (min-width: 2000px) {
                  .novo {
                    color: color-mix(in oklab, var(--color-base-content) 70%, transparent);
                  }
                }
                """)).hasSize(1);
    }

    @Test
    void sobrescritaPosteriorDoMesmoSeletorAprova() {
        assertThat(semSobrescrita("""
                @layer utilities {
                  .tab {
                    &:not(:checked) {
                      @supports (color: color-mix(in lab, red, red)) {
                        color: color-mix(in oklab, var(--color-base-content) 50%, transparent);
                      }
                    }
                  }
                }
                @layer utilities {
                  .tab:not(:checked) {
                    color: color-mix(in oklab, var(--color-base-content) 70%, transparent);
                  }
                }
                """)).isEmpty();
    }

    @Test
    void estadoDesabilitadoFicaDeFora() {
        assertThat(semSobrescrita("""
                .input {
                  &:is(:disabled, [disabled]) {
                    color: color-mix(in oklab, var(--color-base-content) 40%, transparent);
                  }
                }
                """)).isEmpty();
    }

    private static List<String> semSobrescrita(String css) {
        List<Cor> cores = cores(css);
        List<String> semSobrescrita = new ArrayList<>();
        for (Cor cor : cores) {
            if (cor.percentual() >= MINIMO || inativo(cor.seletor())) {
                continue;
            }
            boolean sobrescrita = cores.stream().anyMatch(outra -> outra.linha() > cor.linha()
                    && outra.percentual() >= MINIMO && outra.regra().equals(cor.regra()));
            if (!sobrescrita) {
                semSobrescrita.add(cor.percentual() + "% em " + cor.regra() + " (linha " + cor.linha() + ")");
            }
        }
        return semSobrescrita;
    }

    private static String cssGerado() throws IOException {
        try (InputStream css = ContrasteDoTemaTest.class.getResourceAsStream("/static/css/style.css")) {
            assertThat(css).as("static/css/style.css no classpath; o build do frontend rodou?").isNotNull();
            return new String(css.readAllBytes(), StandardCharsets.UTF_8);
        }
    }

    /**
     * Percorre os blocos aninhados guardando a pilha. {@code @layer} e {@code @supports} não mudam
     * onde a regra vale e ficam de fora da chave; {@code @media} e {@code @container} mudam, e entram
     * nela. O seletor é normalizado para que a regra aninhada do DaisyUI ({@code .tab { &:not(...) }})
     * e a plana do tema ({@code .tab:not(...)}) se comparem.
     */
    private static List<Cor> cores(String css) {
        List<Cor> cores = new ArrayList<>();
        Deque<String> pilha = new ArrayDeque<>();
        String[] linhas = css.split("\n");
        for (int i = 0; i < linhas.length; i++) {
            String linha = linhas[i].strip();
            if (linha.endsWith("{")) {
                pilha.addLast(linha.substring(0, linha.length() - 1).strip());
            } else if (linha.equals("}")) {
                pilha.pollLast();
            } else {
                Matcher cor = COR_ESMAECIDA.matcher(linha);
                if (cor.find()) {
                    String seletor = seletor(pilha);
                    cores.add(new Cor(condicoes(pilha) + seletor, seletor, Integer.parseInt(cor.group(1)), i + 1));
                }
            }
        }
        return cores;
    }

    private static String seletor(Deque<String> pilha) {
        StringBuilder seletor = new StringBuilder();
        for (String nivel : pilha) {
            if (nivel.startsWith("@")) {
                continue;
            }
            if (nivel.startsWith("&")) {
                seletor.append(nivel.substring(1));
            } else {
                seletor.append(seletor.isEmpty() ? "" : " ").append(nivel);
            }
        }
        // O Tailwind imprime `:not( :checked, ... )` com espaços nas regras do DaisyUI e sem espaços na
        // do tema, conforme o resto do arquivo; espaço junto ao parêntese não muda o seletor.
        return seletor.toString().replaceAll("\\s+", " ").replaceAll("\\(\\s+", "(").replaceAll("\\s+\\)", ")").strip();
    }

    private static String condicoes(Deque<String> pilha) {
        StringBuilder condicoes = new StringBuilder();
        for (String nivel : pilha) {
            if (nivel.startsWith("@media") || nivel.startsWith("@container")) {
                condicoes.append(nivel.replaceAll("\\s+", " ")).append(" | ");
            }
        }
        return condicoes.toString();
    }

    /** Desabilitado ou placeholder, sem contar o que está negado: {@code :not(:disabled)} é ativo. */
    private static boolean inativo(String seletor) {
        String semNegacao = seletor;
        for (String anterior = null; !semNegacao.equals(anterior); ) {
            anterior = semNegacao;
            semNegacao = NEGACAO.matcher(semNegacao).replaceAll("");
        }
        return semNegacao.contains("disabled") || semNegacao.contains("placeholder");
    }
}
